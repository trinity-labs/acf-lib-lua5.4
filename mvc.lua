--[[ Basic MVC framework
     Written for Alpine Configuration Framework (ACF)
     see www.alpinelinux.org for more information
     Copyright (C) 2007  Nathan Angelacos
     Licensed under the terms of GPL2
  ]]--
local mymodule = {}

posix = require("posix")
subprocess = require("subprocess")
format = require("acf.format")

-- For security, set the path
posix.setenv("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin")
-- Adjust the package.path to remove .
package.path = string.gsub(package.path, ";?%./%?%.lua", "")

mymodule.mvc = {}

-- the constructor
--[[ Builds a new MVC object.  If "module" is given, then tries to load
	self.conf.appdir ..  module "-controller.lua" in c.worker and
	self.conf.appdir ..  module "-model.lua" in c.model

	The returned  .conf table is guaranteed to have the following
	appdir - where the application lives
	confdir - where the configuration file is
	sessiondir - where session data and other temporary stuff goes
	appname - the name of the application
	]]

mymodule.new = function (self, modname)
	local model_loaded = true
	local worker_loaded = true
	local c = {}
	c.worker = {}
	c.model = {}

	-- make defaults if the parent doesn't have them
	if self.conf == nil then
		c.conf = { appdir = "", confdir = "",
				tempdir = "", appname = "" }
	end

	-- If no clientdata, then clientdata is a null table
	if self.clientdata == nil then
		c.clientdata = {}
	end

	-- If we don't have an application name, use the modname
	if (self.conf == nil ) or (self.conf.appname == nil) then
		c.conf.appname = modname
	end

	-- load the module code here
	if (modname) then
		c.worker = self:soft_require( modname .. "-controller")
		if c.worker == nil then
			c.worker = {}
			worker_loaded = false
		end
		c.model = self:soft_require( modname ..  "-model" )
		if c.model == nil then
			c.model =  {}
			model_loaded = false
		end
	end

	-- The magic that makes all the metatables point in the correct
	-- direction.  c.model -> c.worker -> parent -> parent.worker ->
	-- grandparent -> grandparent -> worker (and so on)

	-- The model looks in worker for missing
	setmetatable (c.model, c.model )
	c.model.__index = c.worker

	-- the worker looks in the parent table for missing
	setmetatable (c.worker, c.worker)
	c.worker.__index = self

	-- the table looks in the worker for missing
	setmetatable (c, c)
	c.__index = c.worker

	-- ensure an "mvc" table exists, even if empty
	if (type(rawget(c.worker, "mvc")) ~= "table") then
		c.worker.mvc = {}
	end

	setmetatable (c.worker.mvc, c.worker.mvc)
	-- If creating a new parent container, then
	-- we are the top of the chain.
	if (modname)  then
		c.worker.mvc.__index = self.worker.mvc
	else
		c.worker.mvc.__index = self.mvc
	end

	-- run the worker on_load code
	if  type(rawget(c.worker.mvc, "on_load")) == "function" then
		c.worker.mvc.on_load(c, self)
		c.worker.mvc.on_load = nil
	end

	-- save the new self on the SELF stack
	if not SELF then SELF = {} end
	SELF[#SELF + 1] = c

	return c, worker_loaded, model_loaded
end

mymodule.destroy = function (self)
	if  type(rawget(self.worker.mvc, "on_unload")) == "function" then
		self.worker.mvc.on_unload(self)
		self.worker.mvc.on_unload = nil
	end

	-- remove the self from the SELF stack (should be at the end, but just in case)
	if SELF then
		for i,s in ipairs(SELF) do
			if s == self then
				table.remove(SELF, i)
				break
			end
		end
	end

	-- remove packages from package.loaded
	if self["_NAME"] then package.loaded[self["_NAME"]] = nil end
	if self.model and self.model["_NAME"] then package.loaded[self.model["_NAME"]] = nil end
end

-- This is a sample front controller/dispatch.
mymodule.dispatch = function (self, userprefix, userctlr, useraction, clientdata)
	local controller = nil
	local success, err = xpcall ( function ()
	self.conf.prefix = userprefix or "/"
	self.conf.controller = userctlr or ""
	self.conf.action = useraction or ""
	if clientdata then self.clientdata = clientdata end

	local worker_loaded
	controller, worker_loaded = self:new(self.conf.prefix .. self.conf.controller)

	if not worker_loaded then
		self.conf.type = "dispatch"
		error(self.conf)
	end

	if controller.conf.action == "" then
		controller.conf.action = rawget(controller.worker, "default_action") or ""
	end

	local action = controller.conf.action

	-- Because of the inheritance, normally the
	-- controller.worker.action will flow up, so that all children have
	-- actions of all parents.  We use rawget to make sure that only
	-- controller defined actions are used on dispatch
	-- If the action is missing, raise an error
	if ( type(rawget(controller.worker, action)) ~= "function") then
		self.conf.type = "dispatch"
		error (self.conf)
	end

	-- run the (first found) pre_exec code, starting at the controller
	-- and moving up the parents
	if  type(controller.worker.mvc.pre_exec) == "function" then
		controller.worker.mvc.pre_exec ( controller )
	end

 	-- run the action
	local viewtable = controller.worker[action](controller)

	-- run the post_exec code
	if  type(controller.worker.mvc.post_exec) == "function" then
		controller.worker.mvc.post_exec ( controller )
	end

	-- Before we start checking for views, set the viewtype
	if self.clientdata.viewtype then
		self.conf.viewtype = self.clientdata.viewtype
	end

	if not self.conf.suppress_view then
		local viewfunc, p1, p2, p3 = controller:view_resolver()
		viewfunc (viewtable, p1, p2, p3)
	end

	-- we're done with the controller, destroy it
	controller:destroy()
	controller = nil

	return viewtable

	end,
	self:soft_traceback(message)
	)

	if not success then
		local handler
		if controller then
			handler = controller.worker or controller
			if handler then handler:exception_handler(err) end
			controller:destroy()
			controller = nil
		end
		if nil == handler then
			handler = self.worker or self.mvc
			handler:exception_handler(err)
		end
	end
end

-- Tries to see if name exists in the self.conf.appdir, and if so, it loads it.
-- otherwise, returns nil, but no error
mymodule.soft_require = function (self, name )
	local filename, file
	for p in string.gmatch(self.conf.appdir, "[^,]+") do
		filename  = p .. name .. ".lua"
		file = io.open(filename)
		if file then
			file:close()
			local PATH=package.path
			-- FIXME - this should really try to open the lua file,
			-- and if it doesnt exist silently fail.
			-- This version allows things from /usr/local/lua/5.1 to
			-- be loaded
			package.path = p .. "/?.lua;" .. package.path
			local t
			if posix.dirname(name) == "." then
				t = require(posix.basename(name))
			else
				t = require(posix.basename(posix.dirname(name)).."."..posix.basename(name))
			end
			package.path = PATH
			return t
		end
	end
	return nil
end

-- look in various places for a config file, and store it in self.conf
mymodule.read_config = function( self, appname, home )
	appname = appname or self.conf.appname
	self.conf.appname = self.conf.appname or appname

	local confs = { (home or "") .. "/." .. appname .. "/" .. appname .. ".conf",
			(home or "") .. "/" .. appname .. ".conf",
			"/etc/" .. appname .. "/" .. appname .. ".conf",
			"/etc/" .. appname .. ".conf"
	}
	for i, filename in ipairs (confs) do
                local file = io.open (filename)
                if (file) then
			self.conf.confdir = posix.dirname(filename) .. "/"
			self.conf.conffile = filename
                        for line in file:lines() do
                                key, value = string.match(line, "^%s*([^[=%s#]*)%s*=%s*(.*)")
                                if key then
                                        self.conf[key]  = value
                                end
			end
                	file:close()
			break
                end
        end

	-- this sets the package path for us and our children
	if self.conf.libdir then
		package.path = string.gsub(self.conf.libdir, ",", "/?.lua;") .. "/?.lua;" .. package.path
	end

	if (#self.conf.confdir) then -- check for an appname-hooks.lua file
		self.conf.app_hooks = {}
		setmetatable (self.conf.app_hooks, {__index = _G})

		local IS_52_LOAD = pcall(load, '')
		if IS_52_LOAD then
			local f = loadfile(self.conf.confdir .. "/" .. appname.. "-hooks.lua", "bt", self.conf.app_hooks)
			if (f) then f() end
		else
			-- loadfile loads into the global environment
			-- so we set env 0, not env 1
			setfenv (0, self.conf.app_hooks)
			local f = loadfile(self.conf.confdir .. "/" .. appname.. "-hooks.lua")
			if (f) then f() end
			setfenv (0, _G)
			-- setmetatable (self.conf.app_hooks, {})
		end
	end

end

-- parse a "URI" like string into a prefix, controller and action
-- return them (or blank strings)
mymodule.parse_path_info = function( str )
	str = str or ""
	local words = {}
	str = string.gsub(str, "/+$", "")
	for x=1,3 do
		words[#words+1] = string.match(str, "[^/]+$")
		str = string.gsub(str, "/+[^/]*$", "")
	end
	prefix = "/"..(words[#words] or "").."/"
	if prefix == "//" then prefix = "/" end
	controller = words[#words-1] or ""
	action = words[#words-2] or ""

	return prefix, controller, action
end

-- look for a view
-- ctlr-action-view, then  ctlr-view
mymodule.find_view = function ( appdir, prefix, controller, action, viewtype )
	if not viewtype then return nil end
	for p in string.gmatch(appdir, "[^,]+") do
		local names = { p .. prefix .. controller .. "-" ..
					action .. "-" .. viewtype .. ".lsp",
				p .. prefix .. controller .. "-" ..
					viewtype .. ".lsp" }
		local file
		-- search for view
		for i,filename in ipairs (names) do
			file = io.open(filename)
			if file then
				file:close()
				return filename
			end
		end
	end
	return nil
end

mymodule.create_helper_library = function ( self )
	local library = {}
--[[	-- If we have a separate library, here's how we could do it
	local library = require("library_name")
	for name,func in pairs(library) do
		if type(func) == "function" then
			library.name = function(...) return func(self, ...) end
		end
	end
--]]
	return library
end

-- The view of last resort
mymodule.auto_view = function(viewtable, viewlibrary, pageinfo, session)
	if pageinfo.viewtype == "html" then
		local htmlviewfunctions = require("htmlviewfunctions")
		htmlviewfunctions.displayitem(viewtable, pageinfo)
	elseif pageinfo.viewtype == "json" then
		local json = require("json")
		print(json.encode(viewtable))
	elseif pageinfo.viewtype == "stream" then
		io.write(tostring(viewtable.value))
	elseif pageinfo.viewtype == "serialized" then
		local s = require("session")
		print(s.serialize("result", viewtable))
	end
end

-- The view resolver of last resort.
mymodule.view_resolver = function(self)
	local viewname, viewlibrary

	-- search for view
	viewname = self.find_view ( self.conf.appdir, self.conf.prefix,
		self.conf.controller, self.conf.action, self.conf.viewtype )

	local func = self.auto_view
	if viewname then
		func = haserl.loadfile (viewname)
	end

	-- create the view helper library
	viewlibrary = self:create_helper_library()

	local pageinfo =  { viewfile = viewname,
				viewtype = self.conf.viewtype,
				controller = self.conf.controller,
				action = self.conf.action,
				prefix = self.conf.prefix,
				script = self.conf.script or "",
				wwwdir = self.conf.wwwdir or "",
				wwwprefix = self.conf.wwwprefix or "",
				staticdir = self.conf.staticdir or "",
				orig_action = self.conf.orig_action or self.conf.prefix .. self.conf.controller .. "/" .. self.conf.action,
				clientdata = self.clientdata,
				}

	return func, viewlibrary, pageinfo, self.sessiondata
end

-- Generates a debug.traceback if called with no arguments
mymodule.soft_traceback = function (self, message )
	if message then
		return message
	else
		return debug.traceback
	end
end

-- The exception hander of last resort
mymodule.exception_handler = function (self, message )
	self.logevent ("The following unhandled application error occured:\n\n")

	if (type(message) == "table" ) then
		if (message.type == "dispatch") then
			self.logevent ('controller: "' .. message.controller .. '" does not have a "' .. message.action .. '" action.')
		else
			self.logevent ("An error of type: '" .. (tostring(message.type) or "nil") .. "' was raised." )
		end
	else
		self.logevent (tostring(message))
	end

	-- Pass the exception to the calling function
	error(message)
end

-- Create a metatable to be used for all cfe objects
local cfe_mt = {}
cfe_mt.__index = cfe_mt
cfe_mt.print_errtxt = function(self)
	local errtxt = {}
	local function get_errtxt(self, name)
		if self.errtxt then
			if name then
				errtxt[#errtxt+1] = name..": "..self.errtxt
			else
				errtxt[#errtxt+1] = self.errtxt
			end
		end
		if "group" == self.type or "form" == self.type then
			if not name then
				name = ""
			else
				name = name.."."
			end
			for n,v in pairs(self.value) do
				get_errtxt(v, name..n)
			end
		end
	end
	get_errtxt(self)
	return table.concat(errtxt, "\n")
end

-- create a Configuration Framework Entity (cfe)
-- returns a table with at least "value", "type", and "label"
mymodule.cfe = function ( optiontable )
	optiontable = optiontable or {}
	me = { 	value="",
		type="text",
		label="" }
	for key,value in pairs(optiontable) do
		me[key] = value
	end
	setmetatable(me, cfe_mt)
	return me
end
_G.cfe = mymodule.cfe

mymodule.logevent = function ( message )
	subprocess.call({"logger", "ACF: " .. (message or "")})
end

mymodule.handle_clientdata = function(form, clientdata)
	clientdata = clientdata or {}
	form.errtxt = nil
	for name,value in pairs(form.value) do
		value.errtxt = nil
		if value.type == "group" then
			mymodule.handle_clientdata(value, clientdata[name])
		elseif not value.readonly then
			value.value = clientdata[name] or value.value
		end
	end
end

mymodule.handle_form = function(self, getFunction, setFunction, clientdata, option, label, descr)
	local form = getFunction(self, clientdata)

	if clientdata.submit then
		self.handle_clientdata(form, clientdata)

		form = setFunction(self, form, clientdata.submit)
		if not form.errtxt and descr then
			form.descr = descr
		end
	end

	form.type = "form"
	form.option = option or form.option
	form.label = label or form.label

	return form
end

return mymodule
