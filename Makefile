build:
	@hugo -d ./build

.PHONY: clean
clean:
	@if [ -d build ]; then rm -r build 2>&1 > /dev/null; fi

.PHONY: dev
dev: URL ?= $(shell emporter get -q 1313)
dev:
	@if [ -z "$(URL)" ]; then echo "*** Emporter URL not found." >&2; exit 1; fi
	@hugo server --baseURL="$(URL)" --appendPort=false --liveReloadPort=443 --buildDrafts

# ----------------------------------------------------------------------------------------

SERVICE := youngdynasty-aws
KEY ?= $(shell security -q find-generic-password -s $(SERVICE) 2> /dev/null | grep acct | cut -d "=" -f 2)
SECRET ?= $(shell security -q find-generic-password -s $(SERVICE) -w 2> /dev/null)
AWS ?= AWS_ACCESS_KEY_ID=$(KEY) AWS_SECRET_ACCESS_KEY=$(SECRET) AWS_DEFAULT_REGION=eu-west-3 aws

.PHONY: creds
creds:
	@if [ -z "$(KEY)" ]; then echo "*** KEY is required."; exit 1; fi 
	@if [ -z "$(SECRET)" ]; then echo "*** SECRET is required."; exit 1; fi 

	@security delete-generic-password -s $(SERVICE) -a $(KEY) > /dev/null 2>&1 || true
	@security add-generic-password -s $(SERVICE) -a $(KEY) -p $(SECRET)

.PHONY: deploy
deploy: clean build
deploy:
	@if [ -z "$(KEY)" ] || [ -z "$(SECRET)" ]; then echo "*** Missing credentials. Run 'make creds' to continue."; exit 1; fi 

	@$(AWS) s3 sync --acl public-read --region eu-west-3 ./build s3://youngdynasty.net
	@$(AWS) cloudfront create-invalidation --distribution E3LP7JN47MB6W0 --paths "/*" > /dev/null

	@echo "OK"

.PHONY: logs
logs: creds
logs: OUTPUT=./logs/goaccess.html
logs:
	@if [ -z "$(shell which goaccess)" ]; then echo "goaccess is required: brew install goaccess"; exit 1; fi

	@[ "$(OFFLINE)" == "1" ] || $(AWS) s3 sync s3://logs.youngdynasty.net ./logs 
	
	@find ./logs -name "*$(DATE)-*.gz" -exec gunzip -c {} \; \
		| LC_ALL=en_US.UTF-8 goaccess - --log-format CLOUDFRONT --no-progress --real-os > $(OUTPUT) \
		&& open $(OUTPUT)
