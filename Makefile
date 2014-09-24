REBAR?=rebar
ERLC ?= $(shell which erlc)
ERL ?= $(shell which erlc)

# test if erlang is installed
$(if $(ERLC),,$(warning "Warning: No Erlang found in your path, this will probably not work"))
$(if $(ERL),,$(warning "Warning: No Erlang found in your path, this will probably not work"))


# build testconf
$(if $(shell erlc -o support/ support/conftest.erl),$(warning "could not compile sample program"),)
$(if $(shell erl -pa support/ -s conftest -noshell),$(warning "could not run sample program"),)

$(if $(wildcard "conftest.out"),$(warning "erlang program was not properly executed, (conftest.out was not produced)"),)


include vsn.mk

ERLANG_EI_DIR=`cat conftest.out | head -n 1`
ERLANG_EI_LIB=`cat conftest.out| head -n 2 | tail -n 1`
ERLANG_DIR?=`cat conftest.out | tail -n 1`

LIB_DIR=$(ERLANG_DIR)/lib/percept2-$(VERSION)


all: build

build:
	@$(REBAR) compile

clean:
	@$(REBAR) clean
	@rm -rf support/conftest.beam
	@rm -f conftest.out

uninstall:
	@-rm -rf ${LIB_DIR}

install: build
	@echo "==> Installing Percept2 in $(LIB_DIR)"
	@install -m 775 -d $(LIB_DIR)/ebin
	@install -m 775 ebin/*.beam $(LIB_DIR)/ebin
	@install -m 775 ebin/*.app $(LIB_DIR)/ebin
	@install -m 775 -d $(LIB_DIR)/src
	@install -m 775 src/*.erl $(LIB_DIR)/src
	@install -m 775 -d $(LIB_DIR)/include
	@install -m 775 include/*.hrl $(LIB_DIR)/include
	@install -m 775 -d $(LIB_DIR)/gplt
	@install -m 775 gplt/*.plt $(LIB_DIR)/gplt
	@install -m 775 -d $(LIB_DIR)/priv
	@install -m 775 -d $(LIB_DIR)/priv/fonts
	@install -m 775 -d $(LIB_DIR)/priv/logs
	@install -m 775 -d $(LIB_DIR)/priv/server_root/conf
	@install -m 775 -d $(LIB_DIR)/priv/server_root/css
	@install -m 775 -d $(LIB_DIR)/priv/server_root/htdocs
	@install -m 775 -d $(LIB_DIR)/priv/server_root/images
	@install -m 775 -d $(LIB_DIR)/priv/server_root/scripts
	@install -m 775 -d $(LIB_DIR)/priv/server_root/svgs
	@install -m 775 priv/fonts/* $(LIB_DIR)/priv/fonts
	@install -m 755 priv/server_root/conf/* $(LIB_DIR)/priv/server_root/conf
	@install -m 755 priv/server_root/css/* $(LIB_DIR)/priv/server_root/css
	@install -m 755 priv/server_root/htdocs/* $(LIB_DIR)/priv/server_root/htdocs
	@install -m 755 priv/server_root/images/* $(LIB_DIR)/priv/server_root/images
	@install -m 755 priv/server_root/scripts/* $(LIB_DIR)/priv/server_root/scripts
