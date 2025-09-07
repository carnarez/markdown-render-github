SHELL=/bin/bash

define DESCRIPTION
\033[1mConvert Markdown content to HTML via the GitHub API and a minimal HTML template.\033[0m

Make use of the GitHub CLI utility and the GitHub API to render Markdown content
into HTML. Beware of the Github API rate limits, detailed on the following page:
https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api.

The documentation about the Markdown endpoints of the GitHub API is available at
the following URL: https://docs.github.com/en/rest/markdown/markdown.

The HTML content served locally is mounted in the container, a simple refresh of
the page should be enough to update it; including CSS styling, although it might
there require a "hard-refresh" to instruct the browser to ignore cached versions
and fetch the stylesheets once again.

Due to the complexity of handling special characters in plain bash, we split the
processing of each Markdown file in five steps:

1. Escape all characters that need escaping through a pass of '| jq -Rrs @json'.
2. Fetch everything *above* the '%ARTICLE%' pattern.
3. Convert some given Markdown content to HTML through a call to the GitHub API.
4. Fetch everything *below* the '%ARTICLE%' pattern.
5. Concatenate the three parts generated above and substitute the last patterns.

This to allow proper debugging if anything goes wrong in any of the steps listed
above, and to help my little brain.
endef

export DESCRIPTION

.DEFAULT_GOAL=help
help:  ## Display this help screen.
	@echo -e "$$DESCRIPTION"
	@echo
	@echo -e "\033[1mAvailable commands\033[0m"
	@grep -E '^[a-z.A-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-12s\033[0m%s\n",$$1,$$2}'

login:  ## Log in to GitHub via the CLI (store the auth token in plain text).
	@gh auth login --git-protocol ssh --hostname github.com --insecure-storage --skip-ssh-key --web

render-all:  ## Convert ALL Markdown content (be aware of GitHub API rate limits).
	@for f in $$( find . -name "*.md" ); do \
	  echo "$${f:2}"; \
	  MAKEFLAGS+=--no-print-directory make render-one IN="$$f"; \
	done

render-one:  ## Convert *one* Markdown file to HTML (selected via the 'IN=' flag).
	@echo "{\"text\": $$( jq --raw-input --raw-output --slurp @json $(IN) )}" > .json
	@sed 's|%ARTICLE%|\n%ARTICLE%|g' template.html | grep --before-context 9999 '%ARTICLE%' | head -n -1 > .html.1
	@gh api --method POST --header "Accept: text/html" --header "X-GitHub-Api-Version: 2022-11-28" /markdown --input .json > .html.2
	@sed 's|%ARTICLE%|%ARTICLE%\n|g' template.html | grep --after-context 9999 '%ARTICLE%' | tail -n +2 > .html.3
	@cat .html.? \
	  | sed "s|%TITLE%|$$( sed 's|^./||g;s|/index.md||g;s|.md||g' <<< $(IN) )|g" \
	  | sed "s|%REPO%|https://github.com/carnarez|g" \
	  | sed "s|%HTTP%||g" \
	  > $$( sed 's|.md|.html|g' <<< $(IN) )
	@rm .html.? .json

serve:  ## Start a minimal HTTP server in a container to test things locally.
	@docker build --file Dockerfile --tag test .
	@docker run --interactive --name test --publish 8080:80 --rm --tty --volume $(PWD):/var/www test
