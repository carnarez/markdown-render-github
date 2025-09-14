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
2. Fetch everything *above* a pattern.
3. Convert some given Markdown content to HTML through a call to the GitHub API.
4. Fetch everything *below* a pattern.
5. Concatenate the three parts generated above and substitute the last patterns.

This to allow proper debugging if anything goes wrong in any of the steps listed
above, and to help my little brain.
endef

export DESCRIPTION

FILE=
HTTP=
REPO=https://github.com/carnarez

.DEFAULT_GOAL=help
help:  ## Display this help screen.
	@echo -e "$$DESCRIPTION"
	@echo
	@echo -e "\033[1mAvailable commands\033[0m"
	@grep -E '^[a-z.A-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-10s  \033[0m%s\n",$$1,$$2}'

login:  ## Log in to GitHub via the CLI (store the auth token in plain text).
	@gh auth login --git-protocol ssh --hostname github.com --insecure-storage --skip-ssh-key --web

render-all:  ## Convert ALL Markdown content (be aware of GitHub API rate limits).
	@[ -f toc.md ] && MAKEFLAGS+=--no-print-directory make render-one-github FILE=toc.md > .toc.html || > .toc.html
	@for f in $$( find . -name "*.md" | grep -v toc.md ); do \
	  echo "$${f:2}"; \
	  MAKEFLAGS+=--no-print-directory make render-one FILE="$$f"; \
	done
	@rm .toc.html

render-one:  ## Convert *one* Markdown file and publish it into our HTML template.
	@cp template.html .html

	@sed 's|%TOCSITE%|\n%TOCSITE%|g' .html | grep --before-context 9999 '%TOCSITE%' | head -n -1 > .html.1
	@cat .toc.html > .html.2
	@sed 's|%TOCSITE%|%TOCSITE%\n|g' .html | grep --after-context 9999 '%TOCSITE%' | tail -n +2 > .html.3
	@cat .html.? > .html
	@rm .html.?

	@sed 's|%TOCPAGE%|\n%TOCPAGE%|g' .html | grep --before-context 9999 '%TOCPAGE%' | head -n -1 > .html.1
	@grep -o '<h[0-9].*>.*</h[0-9]><a.*class="anchor".*>.*</a>' .html | sed 's|<\(h[0-9]\)[^>]*>\(.*\)</h[0-9]><a.*href="\([^"]*\)".*>.*</a>|<\1><a href="\3">\2</a></\1>|g' > .html.2
	@sed 's|%TOCPAGE%|%TOCPAGE%\n|g' .html | grep --after-context 9999 '%TOCPAGE%' | tail -n +2 > .html.3
	@cat .html.? > .html
	@rm .html.?

	@sed 's|%ARTICLE%|\n%ARTICLE%|g' .html | grep --before-context 9999 '%ARTICLE%' | head -n -1 > .html.1
	@MAKEFLAGS+=--no-print-directory make render-one-github FILE="$(FILE)" > .html.2
	@sed 's|%ARTICLE%|%ARTICLE%\n|g' .html | grep --after-context 9999 '%ARTICLE%' | tail -n +2 > .html.3
	@cat .html.? > .html
	@rm .html.?

	@cat .html \
	  | sed "s|%TITLE%|$$( sed 's|^./||g;s|/index.md||g;s|.md||g' <<< $(FILE) )|g" \
	  | sed "s|%REPO%|$(REPO)|g" \
	  | sed "s|%HTTP%|$(HTTP)|g" \
	  | sed "s|%[A-Z]+%||g" \
	  > $$( sed 's|.md|.html|g' <<< $(FILE) )

	@rm .html

render-one-github:  ## Convert a given Markdown file into HTML via the GitHub API.
	@echo "{\"text\": $$( jq --raw-input --raw-output --slurp @json $(FILE) )}" > .json
	@gh api --method POST --header "Accept: text/html" --header "X-GitHub-Api-Version: 2022-11-28" /markdown --input .json
	@rm .json

serve:  ## Start a minimal HTTP server in a container to test things locally.
	@docker build --file Dockerfile --tag test .
	@docker run --interactive --name test --publish 8080:80 --rm --tty --volume $(PWD):/var/www test
