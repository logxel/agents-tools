.PHONY: skills-add skills-add-command skills-audit skills-validate skills-check skills-update opencode-validate

skills-add:
	@test -n "$(SOURCE)" || (echo "SOURCE is required, e.g. make skills-add SOURCE=sveltejs/ai-tools SKILL=svelte-core-bestpractices" && exit 1)
	@test -n "$(SKILL)" || (echo "SKILL is required, e.g. make skills-add SOURCE=sveltejs/ai-tools SKILL=svelte-core-bestpractices" && exit 1)
	./.github/scripts/add-skill.sh "$(SOURCE)" --skill "$(SKILL)"

skills-add-command:
	@test -n "$(COMMAND)" || (echo "COMMAND is required, e.g. make skills-add-command COMMAND=\"npx skills add https://github.com/sickn33/antigravity-awesome-skills --skill typescript-expert\"" && exit 1)
	./.github/scripts/add-skill.sh --from-command "$(COMMAND)"

skills-audit:
	./.github/scripts/audit-skills.sh --write

skills-validate:
	./.github/scripts/validate-skills.sh --all

skills-check:
	npx --yes skills check

skills-update:
	./.github/scripts/update-skills.sh

opencode-validate:
	./.github/scripts/validate-opencode-addon.sh
