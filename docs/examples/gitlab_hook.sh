#!/bin/sh -e
#
# dehydrated hook script to deploy a key to Gitlab.
#
# Add the following options to your config file:
# TOKEN= API token, generate in Gitlab profile settings (select API access)
# PROJECT= project ID on Gitlab (general project settings)
# REPO= path to local git repo of your pages project

. "$BASEDIR/$CONFIG"

deploy_challenge() {
  DOMAIN="$1"
  TOKEN_FILENAME="$2"
  cd "$REPO"
  mkdir -p public/.well-known/acme-challenge
  cp "$WELLKNOWN/$TOKEN_FILENAME" public/.well-known/acme-challenge/
  git add public/.well-known/acme-challenge/"$TOKEN_FILENAME"
  git commit -m "Let's Encrypt challenge"
  git push
  sleep 20
  while ! curl --output /dev/null --silent --head --fail "http://$DOMAIN/.well-known/acme-challenge/$TOKEN_FILENAME"; do
    echo sleeping
    sleep 5
  done
}

clean_challenge() {
  TOKEN_FILENAME="$2"
  cd "$REPO"
  git reset --hard HEAD~
  git push --force-with-lease
}

deploy_cert() {
  DOMAIN="$1"
  KEYFILE="$2"
  FULLCHAINFILE="$4"
  curl --request PUT --header "PRIVATE-TOKEN: $TOKEN" --form "certificate=@$FULLCHAINFILE" --form "key=@$KEYFILE" "https://gitlab.com/api/v4/projects/$PROJECT/pages/domains/$DOMAIN"
}

HANDLER="$1"; shift
case "$HANDLER" in
  deploy_challenge)
    deploy_challenge "$@"
  ;;
  clean_challenge)
    clean_challenge "$@"
  ;;
  deploy_cert)
    deploy_cert "$@"
  ;;
esac
