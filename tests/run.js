const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const interop = require('fengari-interop');
global.nodefs = require('fs');
global.nodepath = require('path');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lauxlib.luaL_requiref(L, to_luastring('js'), interop.luaopen_js, 1);
lua.lua_pop(L, 1);
global.PLUGIN_DIR = process.argv[3];
global.WORK_DIR = process.argv[4];
if (lauxlib.luaL_dofile(L, to_luastring(process.argv[2])) !== lua.LUA_OK) {
  console.log('LUA ERROR:', to_jsstring(lua.lua_tostring(L, -1)));
  process.exitCode = 1;
}
