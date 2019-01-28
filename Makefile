build:
	@hugo -d ./build

.PHONY: clean
clean:
	@rm -r build
	 
.PHONY: dev
dev: URL ?= https://blog-u68g.emporter.eu
dev:
	@hugo server --baseURL="$(URL)" --appendPort=false --liveReloadPort=443 --buildDrafts

# ----------------------------------------------------------------------------------------

SERVICE := youngdynasty-aws
KEY ?= $(shell security -q find-generic-password -s $(SERVICE) 2> /dev/null | grep acct | cut -d "=" -f 2)

.PHONY: creds
creds:
	@if [ -z "$(KEY)" ]; then echo "*** KEY is required."; exit 1; fi 
	@if [ -z "$(SECRET)" ]; then echo "*** SECRET is required."; exit 1; fi 

	@security delete-generic-password -s $(SERVICE) -a $(KEY) > /dev/null 2>&1 || true
	@security add-generic-password -s $(SERVICE) -a $(KEY) -p $(SECRET)

.PHONY: deploy
deploy: clean build
deploy: SECRET ?= $(shell security -q find-generic-password -s $(SERVICE) -w 2> /dev/null)
deploy:
	@if [ -z "$(KEY)" ] || [ -z "$(SECRET)" ]; then echo "*** Missing credentials. Run 'make creds' to continue."; exit 1; fi 

	@set -a \
		&& AWS_ACCESS_KEY_ID=$(KEY) AWS_SECRET_ACCESS_KEY=$(SECRET) \
		&& aws s3 sync --acl public-read ./build s3://youngdynasty.net \
		&& aws cloudfront create-invalidation --distribution E3LP7JN47MB6W0 --paths "/*" > /dev/null

	@echo "OK"
