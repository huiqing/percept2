REBAR?=rebar

all: build

build:
	@$(REBAR) compile

clean:
	@$(REBAR) clean
