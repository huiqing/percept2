APPNAME = percept2

include vsn.mk

prefix       = /home/hl
exec_prefix  = ${prefix}
libdir       = ${exec_prefix}/lib
LIB_DIR      = ${libdir}/erlang/lib/$(APPNAME)-$(VERSION)
ERL          = "\erl5.9.1\bin/erl"
ERLC         = "\erl5.9.1\bin/erlc"

ERL_SRC = $(wildcard src/*.erl)

ERL_OBJ = $(patsubst src/%.erl,ebin/%.beam,$(ERL_SRC))

.PHONY: default all conf erl 

default: erl

erl: $(ERL_OBJ)

c:
	@cd ./c_src; make; cd ../..

########################################
## Rules

.SUFFIXES: .erl 

## Erlang
ebin/%.beam: src/%.erl
	$(ERLC) -pa ebin -I include -W -o ebin +debug_info $<

ebin/%.beam: src/percept.hrl 

########################################


clean:
	@-rm -f ${ERL_OBJ}

distclean: clean


install: default
	@echo "* Installing Percept"
	install -m 775 -d $(LIB_DIR)/ebin
	install -m 775 ebin/*.beam $(LIB_DIR)/ebin
	install -m 775 ebin/*.app $(LIB_DIR)/ebin
	install -m 775 -d $(LIB_DIR)/src
	install -m 775 src/*.erl $(LIB_DIR)/src
	install -m 775 -d $(LIB_DIR)/include
	install -m 775 include/*.hrl $(LIB_DIR)/include
	install -m 775 -d $(LIB_DIR)/priv
	install -m 775 -d $(LIB_DIR)/priv/fonts	
	install -m 775 -d $(LIB_DIR)/priv/logs	
	install -m 775 -d $(LIB_DIR)/priv/server_root	
	install -m 775 priv/fonts/* $(LIB_DIR)/priv/fonts
	install -m 775 priv/fonts/* $(LIB_DIR)/priv/logs
	install -m 775 priv/fonts/* $(LIB_DIR)/priv/server_root		
	@echo
	@echo "*** Successfully installed."
	@echo
