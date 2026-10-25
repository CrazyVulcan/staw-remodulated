// Offline Lua regression checks. Fengari is Lua 5.3, not TTS/MoonSharp.
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = fengari;
const root = __dirname;

const results = {engine: 'Fengari 0.1.5 / Lua 5.3; mocked TTS API', syntax: [], embeddedSyntax: [], tests: [], logs: []};
function push(L, value) {
  if (value == null) lua.lua_pushnil(L);
  else if (typeof value === 'string') lua.lua_pushstring(L, to_luastring(value));
  else if (typeof value === 'number') lua.lua_pushnumber(L, value);
  else if (typeof value === 'boolean') lua.lua_pushboolean(L, value);
  else if (Array.isArray(value)) {
    lua.lua_createtable(L, value.length, 0);
    value.forEach((v, i) => { push(L, v); lua.lua_rawseti(L, -2, i + 1); });
  } else {
    lua.lua_newtable(L);
    for (const [k, v] of Object.entries(value)) { push(L, v); lua.lua_setfield(L, -2, to_luastring(k)); }
  }
}
function read(L, index, seen = new Set()) {
  index = lua.lua_absindex(L, index);
  switch (lua.lua_type(L, index)) {
    case lua.LUA_TNIL: return null;
    case lua.LUA_TBOOLEAN: return !!lua.lua_toboolean(L, index);
    case lua.LUA_TNUMBER: return lua.lua_tonumber(L, index);
    case lua.LUA_TSTRING: return to_jsstring(lua.lua_tolstring(L, index));
    case lua.LUA_TTABLE: {
      const pointer = lua.lua_topointer(L, index);
      if (seen.has(pointer)) throw Error('JSON cycle');
      seen.add(pointer);
      const obj = {}, entries = [];
      lua.lua_pushnil(L);
      while (lua.lua_next(L, index)) {
        const key = read(L, -2, seen), value = read(L, -1, seen);
        obj[key] = value; entries.push([key, value]); lua.lua_pop(L, 1);
      }
      seen.delete(pointer);
      const n = lua.lua_rawlen(L, index);
      return n > 0 && entries.length === n && entries.every(([k]) => Number.isInteger(k) && k >= 1 && k <= n)
        ? Array.from({length: n}, (_, i) => obj[i + 1]) : obj;
    }
    default: throw Error('JSON unsupported Lua type ' + lua.lua_type(L, index));
  }
}
function cfunction(L, name, fn) {
  lua.lua_pushjsfunction(L, state => {
    try { return fn(state); }
    catch (e) { push(state, e.message); return lua.lua_error(state); }
  });
  lua.lua_setglobal(L, to_luastring(name));
}
function execute(L, source, name) {
  let status = lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring('@' + name));
  if (status === lua.LUA_OK) status = lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) { const err = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); throw Error(err); }
}

module.exports={push,read,cfunction,execute,results,lua,lauxlib,lualib,to_luastring,to_jsstring};
