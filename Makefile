.PHONY: \
	all \
	bump-minor-vsn \
	bump-patch-vsn \
	check \
	compile \
	console \
	get-deps \
	dialyzer \
	prepare-deps \
	test

REBAR := rebar3

# Ensure snappyer compiles with newer toolchains.
export CXXFLAGS ?= -include cstdint

all: test dialyzer

bump-minor-vsn:
	bumperl -a src/dbmigrate.app.src -t -c -l minor
	git push origin develop
	git push --tags

bump-patch-vsn:
	bumperl -a src/dbmigrate.app.src -t -c -l patch
	git push origin develop
	git push --tags

check: test dialyzer

console:
	@$(REBAR) shell --sname dbmigrate

compile:
	@$(REBAR) compile

prepare-deps:
	@$(REBAR) get-deps
	@MOCHIWEB_FILE="_build/default/lib/mochiweb/src/mochiweb_multipart.erl"; \
	if [ -f "$$MOCHIWEB_FILE" ]; then \
		sed -i "s/{maybe,/{'maybe',/g" "$$MOCHIWEB_FILE"; \
	fi

dialyzer: $(OTP_PLT) prepare-deps
	@$(REBAR) dialyzer

get-deps:
	@$(REBAR) get-deps

test: prepare-deps
	@$(REBAR) do eunit,ct
