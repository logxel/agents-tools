from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class JsonMember:
    key: str
    value: JsonNode


@dataclass
class JsonNode:
    kind: str
    start: int
    end: int = 0
    value: Any = None
    properties: list[JsonMember] = field(default_factory=list)
    items: list[JsonNode] = field(default_factory=list)


class JsoncParser:
    def __init__(self, text: str, file_path: str) -> None:
        self.text = text
        self.file_path = file_path
        self.index = 0
        self.decoder = json.JSONDecoder(parse_constant=self.reject_constant)

    def fail(self) -> None:
        raise ValueError(f"{self.file_path}: invalid JSONC at character {self.index}")

    def reject_constant(self, _value: str) -> None:
        self.fail()

    def skip_trivia(self) -> None:
        while self.index < len(self.text):
            if self.text[self.index].isspace():
                self.index += 1
            elif self.text.startswith("//", self.index):
                newline = self.text.find("\n", self.index + 2)
                self.index = len(self.text) if newline < 0 else newline + 1
            elif self.text.startswith("/*", self.index):
                end = self.text.find("*/", self.index + 2)
                if end < 0:
                    self.fail()
                self.index = end + 2
            else:
                return

    def parse_string(self) -> str:
        try:
            value, end = self.decoder.raw_decode(self.text, self.index)
        except json.JSONDecodeError:
            self.fail()
        if not isinstance(value, str):
            self.fail()
        self.index = end
        return value

    def parse_value(self) -> JsonNode:
        self.skip_trivia()
        start = self.index
        if self.index >= len(self.text):
            self.fail()

        if self.text[self.index] == "{":
            self.index += 1
            node = JsonNode("object", start)
            while True:
                self.skip_trivia()
                if self.index >= len(self.text):
                    self.fail()
                if self.text[self.index] == "}":
                    self.index += 1
                    node.end = self.index
                    return node
                if self.text[self.index] != '"':
                    self.fail()
                key = self.parse_string()
                self.skip_trivia()
                if self.index >= len(self.text) or self.text[self.index] != ":":
                    self.fail()
                self.index += 1
                node.properties.append(JsonMember(key, self.parse_value()))
                self.skip_trivia()
                if self.index < len(self.text) and self.text[self.index] == ",":
                    self.index += 1
                elif self.index >= len(self.text) or self.text[self.index] != "}":
                    self.fail()

        if self.text[self.index] == "[":
            self.index += 1
            node = JsonNode("array", start)
            while True:
                self.skip_trivia()
                if self.index >= len(self.text):
                    self.fail()
                if self.text[self.index] == "]":
                    self.index += 1
                    node.end = self.index
                    return node
                node.items.append(self.parse_value())
                self.skip_trivia()
                if self.index < len(self.text) and self.text[self.index] == ",":
                    self.index += 1
                elif self.index >= len(self.text) or self.text[self.index] != "]":
                    self.fail()

        try:
            value, end = self.decoder.raw_decode(self.text, self.index)
        except json.JSONDecodeError:
            self.fail()
        self.index = end
        return JsonNode("value", start, end, value)

    def parse(self) -> JsonNode:
        root = self.parse_value()
        self.skip_trivia()
        if self.index != len(self.text):
            self.fail()
        return root


def to_value(node: JsonNode) -> Any:
    if node.kind == "array":
        return [to_value(item) for item in node.items]
    if node.kind == "object":
        result: dict[str, Any] = {}
        for member in node.properties:
            result[member.key] = to_value(member.value)
        return result
    return node.value


def get_property(node: JsonNode, key: str) -> JsonMember | None:
    return next((member for member in reversed(node.properties) if member.key == key), None)


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ": "))


def merge_config(config_path: str, addon_path: str, enable_ast_grep: bool, ast_grep_path: str) -> None:
    config_text = Path(config_path).read_text(encoding="utf-8")
    config_root = JsoncParser(config_text, config_path).parse()
    addon_root = JsoncParser(Path(addon_path).read_text(encoding="utf-8"), addon_path).parse()
    if config_root.kind != "object" or addon_root.kind != "object":
        raise ValueError("OpenCode configuration must be a JSON object")

    addon = to_value(addon_root)
    additions: dict[int, tuple[JsonNode, list[Any]]] = {}
    replacements: list[tuple[int, int, str]] = []

    def add_object_entries(node: JsonNode, entries: list[tuple[str, Any]]) -> None:
        if node.kind != "object":
            raise ValueError(f"{config_path}: expected an object while merging addon")
        missing = [(key, value) for key, value in entries if get_property(node, key) is None]
        if missing:
            queued = additions.setdefault(id(node), (node, []))[1]
            queued.extend(missing)

    def add_array_items(node: JsonNode, values: list[Any]) -> None:
        if node.kind != "array":
            raise ValueError(f"{config_path}: expected an array while merging addon")
        existing = to_value(node)
        missing = [value for value in values if value not in existing]
        if missing:
            queued = additions.setdefault(id(node), (node, []))[1]
            queued.extend(missing)

    schema = get_property(config_root, "$schema")
    if schema is None:
        add_object_entries(config_root, [("$schema", addon["$schema"])])
    if get_property(config_root, "default_agent") is None:
        add_object_entries(config_root, [("default_agent", addon["default_agent"])])

    agents = get_property(config_root, "agents")
    if agents is None:
        add_object_entries(config_root, [("agents", addon["agents"])])
    else:
        if agents.value.kind != "object":
            raise ValueError(f"{config_path}: agents must be an object to merge the addon")
        add_object_entries(agents.value, list(addon["agents"].items()))

    for name in ("skills", "permissions"):
        entry = get_property(config_root, name)
        if entry is None:
            add_object_entries(config_root, [(name, addon[name])])
            continue
        if entry.value.kind != "array":
            raise ValueError(f"{config_path}: {name} must be an array to merge the addon")
        existing = to_value(entry.value)
        if name == "permissions":
            missing = [
                default
                for default in addon[name]
                if not any(
                    isinstance(item, dict)
                    and item.get("action") == default.get("action")
                    and item.get("resource") == default.get("resource")
                    for item in existing
                )
            ]
        else:
            missing = [default for default in addon[name] if default not in existing]
        add_array_items(entry.value, missing)

    if enable_ast_grep:
        fragment = to_value(JsoncParser(Path(ast_grep_path).read_text(encoding="utf-8"), ast_grep_path).parse())
        server_defaults = dict(fragment["mcp"]["servers"]["ast-grep"])
        server_defaults["disabled"] = False
        mcp = get_property(config_root, "mcp")
        if mcp is None:
            add_object_entries(config_root, [("mcp", {"servers": {"ast-grep": server_defaults}})])
        else:
            if mcp.value.kind != "object":
                raise ValueError(f"{config_path}: mcp must be an object to enable AST-grep")
            servers = get_property(mcp.value, "servers")
            if servers is None:
                add_object_entries(mcp.value, [("servers", {"ast-grep": server_defaults})])
            else:
                if servers.value.kind != "object":
                    raise ValueError(f"{config_path}: mcp.servers must be an object to enable AST-grep")
                ast_grep = get_property(servers.value, "ast-grep")
                if ast_grep is None:
                    add_object_entries(servers.value, [("ast-grep", server_defaults)])
                else:
                    if ast_grep.value.kind != "object":
                        raise ValueError(f"{config_path}: mcp.servers.ast-grep must be an object")
                    disabled = get_property(ast_grep.value, "disabled")
                    if disabled is None:
                        add_object_entries(ast_grep.value, [("disabled", False)])
                    elif to_value(disabled.value) is not False:
                        replacements.append((disabled.value.start, disabled.value.end, "false"))

    edits = list(replacements)
    for node, entries in additions.values():
        children = [member.value for member in node.properties] if node.kind == "object" else node.items
        last_child = children[-1] if children else None
        position = last_child.end if last_child else node.start + 1
        if node.kind == "object":
            rendered = [
                f"{json.dumps(key, ensure_ascii=False)}: {json_text(value)}"
                for key, value in entries
            ]
        else:
            rendered = [json_text(value) for value in entries]
        edits.append((position, position, f"{', ' if last_child else ''}{', '.join(rendered)}"))

    merged_text = config_text
    for start, end, text in sorted(edits, key=lambda edit: edit[0], reverse=True):
        merged_text = merged_text[:start] + text + merged_text[end:]
    JsoncParser(merged_text, config_path).parse()
    if merged_text != config_text:
        Path(config_path).write_text(merged_text, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 5:
        print("Usage: merge-config.py CONFIG ADDON_CONFIG ENABLE_AST_GREP AST_GREP_CONFIG", file=sys.stderr)
        return 2
    config_path, addon_path, ast_enabled, ast_grep_path = sys.argv[1:]
    try:
        merge_config(config_path, addon_path, ast_enabled == "1", ast_grep_path)
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
