#!/usr/local/bin/lua

--[[
	undoc 1.1
	by Jonathan Stoler
	https://github.com/jonstoler
--]]

local parser = {
	name = "undoc",
	author = "Jonathan Stoler",
	url = "https://github.com/jonstoler/undoc",
	version = "1.1",
	decimalVersion = 1.1,
}

local function trim(l)
	return l:gsub("^%s*(.-)%s*$", "%1")
end

local function osPath(p)
	return p:gsub("/", package.config:sub(1, 1))
end

local function path(p)
	return p:gsub(package.config:sub(1, 1), "/")
end

local function split(str, delim)
	if str == "" then return {} end
	local result = {}
	for match in (str .. delim):gmatch("(.-)" .. delim) do
		table.insert(result, match)
	end
	return result
end

local scopeLevel = {
	package = 1,
	class = 2,
	["function"] = 3,
	constructor = 3,
	variable = 4,
	code = 5,
	document = 6,
}

local function Node(type, value)
	return {
		parent = false,
		children = {},
		type = type or "node",
		value = value or "",
		data = {},
		scopeLevel = scopeLevel[type] or #scopeLevel + 1,
		up = function(self)
			if self.parent then return self.parent end
			return self
		end,
		upTo = function(self, type)
			local node = self
			while(node.parent) do
				if node.scopeLevel < scopeLevel[type] then
					return node
				end
				if not node.parent then return node end
				node = node.parent
			end
			return node
		end,
		add = function(self, child)
			child.parent = self
			table.insert(self.children, child)
			return child
		end,
		has = function(self, searchValue)
			for k, v in pairs(self.children) do
				if v.value == searchValue then return v end
			end
			return nil
		end
	}
end

local function err(errStr)
	print("ERROR: " .. errStr)
	os.exit(-1)
end

local function fileLines(filename)
	local function file_exists(file)
		local f = io.open(file, "r")
		return (f ~= nil)
	end

	if not filename or filename == "" then
		err("No input file was specified.")
	end
	if not file_exists(filename) then
		err("The file " .. filename .. " does not exist.")
	end

	local lines = {}
	for line in io.lines(filename) do
		table.insert(lines, line)
	end

	return lines
end


-- start an empty tree
local tree = Node("document")
scope = tree

local filename = arg[1]
local output = arg[2]

local pattern = {
	comment = "^//",
	whitespace = "^%s-$",
	back = "^%s-%<%s*$",
	inlineback = "^%s*<%s*(.+)$",
	package = "^%[(.+)%](.-)$",
	class = "^(.-):$",
	classdescription = "^(.-):%s-=%s*(.-)$",
	subclass = "(.-)%s-%->%s*(.-)$",
	description = "^%s-=%s*(.-)$",
	inlinedescription = "%s-=%s*(.-)$",
	code = "^(%s-)>>(.-)$",
	func = "^([^=]-)%((.-)%)(.-)$",
	funcreturn = "%s-%->%s*(.-)$",
	returndescription = "%->%s*(.-)$",
	typedvariable = "^(.-):(.-)$",
	defaultvariable = "^(.-)@(.-)$",
	fileinclude = "%s-!%s*(.-)$",
}

function processFile(filename)
	local lines = fileLines(filename)
	local currentLine = 1
	local currentReturn = 1

	local filepath = split(path(filename), "/")
	table.remove(filepath)
	filepath = table.concat(filepath, "/") .. "/"

	while(currentLine <= #lines) do
		local line = lines[currentLine]
		line = trim(line)

		-- used later for function arguments
		local i = 0

		-- ignore comments and whitespace
		if not line:match(pattern.comment) and not line:match(pattern.whitespace) then
			-- store then clear inline back operators if present
			local back = line:match(pattern.inlineback) or false
			if back then line = line:gsub(pattern.inlineback, "%1") end
			
			-- things that come after the "main" line (mostly for descriptions)
			local post = nil

			if line:match(pattern.fileinclude) then
				local file = line:gsub(pattern.fileinclude, "%1")
				processFile(osPath(filepath .. file))
			elseif line:match(pattern.back) then
				scope = scope:up()
			elseif line:match(pattern.package) then
				-- for descriptions
				post = line:gsub(pattern.package, "%2")

				line = line:gsub(pattern.package, "%1")
				
				-- convert to dot notation
				line = line:gsub("/", ".")
				
				-- package components
				local pkgs = {}
				for m in line:gmatch("[^%.]*") do
					if m ~= "" then
						table.insert(pkgs, m)
					end
				end

				-- create package hierarchy even if components weren't defined previously
				scope = scope:upTo("package")
				for k, v in pairs(pkgs) do
					local has = scope:has(v)
					if not has then
						scope = scope:add(Node("package", v))
					else
						scope = has
					end
				end
			elseif line:match(pattern.class) or line:match(pattern.classdescription) then
				-- capture description
				post = line:gsub(pattern.classdescription, "%2")

				scope = scope:upTo("class")

				if line:match(pattern.classdescription) then
					line = line:gsub(pattern.classdescription, "%1")
					-- the pattern strips the "= " so we have to add it back
					post = "= " .. post
				else
					line = line:gsub(pattern.class, "%1")
				end

				local classname = line
				local super = {}

				if line:match(pattern.subclass) then
					-- set superclasses and strip them from classname
					classname = line:gsub(pattern.subclass, "%1")
					super = split(line:gsub(pattern.subclass, "%2"), ",%s*")
				end

				local n = Node("class", classname)
				if #super > 0 then n.data.superclass = super end

				if back then
					scope = scope:up():add(n)
				else
					scope = scope:add(n)
				end
			elseif line:match(pattern.description) then
				-- if the whole line is a description
				local d = line:gsub(pattern.description, "%1")

				-- append to existing description or make one if necessary
				if scope.data.description then
					table.insert(scope.data.description, d)
				else
					scope.data.description = {d}
				end
			elseif line:match(pattern.code) then
				-- whitespace to strip from inner code
				local whitespace = lines[currentLine]:gsub(pattern.code, "%1")

				-- code title (if present)
				local title = line:gsub(pattern.code, "%2")

				local cL = currentLine + 1
				local code = ""
				
				-- keep going until the code closes or we reach EOF
				while(not lines[cL]:match(pattern.code) and cL <= #lines) do
					-- strip whitespace
					for i = 1, whitespace:len() do
						if lines[cL]:sub(1, 1):match("%s") then
							lines[cL] = lines[cL]:sub(2)
						end
					end

					code = code .. lines[cL] .. "\n"
					cL = cL + 1
				end

				-- remove trailing linebreak
				code = code:sub(1, -1)

				-- code language (if present)
				local lang = lines[cL]:gsub(pattern.code, "%2")

				if title == "" then title = "code" end
				local n = Node("code", title)
				n.data.code = code
				if lang then n.data.language = lang end
				-- don't change scope because code can't have children
				scope:add(n)

				-- account for all the code lines we processed
				currentLine = cL
			elseif line:match(pattern.func) then
				-- reset return counter (for return descriptions)
				currentReturn = 1

				-- descriptions
				post = line:gsub(pattern.func, "%3")

				local name = line:gsub(pattern.func, "%1")
				local arguments = line:gsub(pattern.func, "%2")
				local access = nil

				-- handle special function types
				if name:sub(1, 1) == "." then
					access = "static"
					name = name:sub(2)
				elseif name:sub(1, 1) == "*" then
					access = "private"
					name = name:sub(2)
				end

				arguments = split(arguments, ",%s*")

				-- return types
				local ret = ""
				if post:match(pattern.funcreturn) then
					ret = post:gsub(pattern.funcreturn, "%1")

					-- get description if it's there
					if ret:match(pattern.inlinedescription) then
						local index = ret:find(pattern.inlinedescription)
						post = ret:sub(index)
						ret = ret:sub(1, index)
						ret = trim(ret)
					end
				end
				ret = split(ret, ",%s*")

				scope = scope:upTo("function")

				local type = (name ~= "" and "function" or "constructor")
				local n = Node(type, name ~= "" and name or "constructor")
				if #arguments > 0 then n.data.arguments = arguments end
				if ret and #ret > 0 then n.data.returns = ret end
				if access then n.data.scope = access end
				scope = scope:add(n)
			elseif line:match(pattern.returndescription) then
				line = line:gsub(pattern.returndescription, "%1")

				scope = scope:upTo("variable")

				if scope.data.returns and currentReturn <= #scope.data.returns then
					scope.data.returns[currentReturn] = {
						type = scope.data.returns[currentReturn],
						description = line
					}
					currentReturn = currentReturn + 1
				end
			else -- variable
				local name, type, default

				if line:match(pattern.inlinedescription) then
					local index = line:find(pattern.inlinedescription)
					post = line:sub(index)
					line = line:sub(1, index - 1)
				end

				if line:match(pattern.typedvariable) then
					name = line:gsub(pattern.typedvariable, "%1")
					type = line:gsub(pattern.typedvariable, "%2")
					if line:match(pattern.defaultvariable) then
						default = line:gsub(pattern.defaultvariable, "%2")
						type = type:gsub("(.-)%s*@.*", "%1")
					end
				elseif line:match(pattern.defaultvariable) then
					name = line:gsub(pattern.defaultvariable, "%1")
					default = line:gsub(pattern.defaultvariable, "%2")
					name = trim(name)
				else
					name = trim(line)
				end

				local access = false
				if name:sub(1, 1) == "." then
					access = "static"
					name = name:sub(2)
				elseif name:sub(1, 1) == "*" then
					access = "private"
					name = name:sub(2)
				elseif name:sub(1, 1) == "~" then
					access = "optional"
					name = name:sub(2)
				end

				scope = scope:upTo("variable")
				if back then scope = scope:up() end

				i = 0
				if scope.type == "function" or scope.type == "constructor" then
					for k, v in pairs(scope.data.arguments) do
						if v == name and i == 0 then i = k end
					end
				end

				if i > 0 then
					scope.data.arguments[i] = {
						name = name,
						type = "variable",
						class = type,
						scope = access or nil,
						default = default,
					}
				else
					local n = Node("variable", name)
					n.data.default = default
					n.data.class = type
					n.data.scope = access or nil
					scope = scope:add(n)
				end
			end

			-- inline descriptions!
			if post and post:match(pattern.inlinedescription) then
				local d = post:gsub(pattern.inlinedescription, "%1")
				if i > 0 then
					scope.data.arguments[i].description = {d}
				else
					scope.data.description = {d}
				end
			end
		end
		currentLine = currentLine + 1
	end
end

local function process(node)
	local tbl = {}
	if node.type ~= "document" then
		tbl.type = node.type
		for k, v in pairs(node.data) do
			tbl[k] = v
		end
	end
	tbl.children = {}
	for k, v in pairs(node.children) do
		if v.value ~= "" then
			local t = process(v)
			t.name = v.value
			table.insert(tbl.children, t)
		else
			table.insert(tbl.children, process(v))
		end
	end
	return tbl
end

processFile(filename)
local processedTree = process(tree).children or {}

local function serialize(table)
	local level = 1
	local out = ""
	
	local function indent()
		local l = (level >= 0 and level or 0)
		return string.rep("\t", l)
	end

	local function process(tbl)
		for k, v in pairs(tbl) do
			if type(v) == "table" then
				if type(k) == "number" then
					out = out .. indent() .. "{" .. "\n"
				else
					out = out .. indent() .. '["' .. k .. '"]' .. " = {" .. "\n"
				end
				level = level + 1
				out = process(v)
				out = out .. indent() .. "}" .. ",\n"
			else
				if type(k) == "number" then
					out = out .. indent()
				else
					out = out .. indent() .. '["' .. k .. '"]' .. " = "
				end
				if type(v) == "string" then
					if v:match("\n") then
						out = out .. '[[' .. tostring(v) .. ']]'
					else
						out = out .. '"' .. tostring(v):gsub('"', '\\"') .. '"'
					end
				else
					out = out .. tostring(v)
				end
				out = out .. ",\n"
			end
		end
		level = level - 1

		return out
	end

	process(table)
	out = "{\n" .. string.sub(out, 1, -2) .. "\n}"
	return out
end

if output then
	local f = io.open(output, "w")
	if not f then
		err("The file " .. output .. " could not be written.")
	end
	f:write("return " .. serialize(processedTree) .. ",\n" .. serialize(parser))
	f:close()
else
	print("return " .. serialize(processedTree) .. ",\n" .. serialize(parser))
end
