# undoc

**current version: 1.1.1 - July 27, 2014**

## Table of Contents

## Contents

- [Goals](#goals)
- [Implementation](#implementation)
- [Usage](#usage)
- [Language](#language)
    - [whitespace](#whitespace)
    - [comments](#comments)
    - [scoping](#scoping)
    - [back operator](#back-operator)
    - [includes](#includes)
- [Elements](#elements)
    - [packages](#packages)
    - [classes](#classes)
    - [descriptions](#descriptions)
    - [example code](#example-code)
    - [functions](#functions)
        - [static functions](#static-functions)
        - [private](#private)
        - [constructors](#constructors)
    - [variables](#variables)
    - [using functions and variables together](#using-functions-and-variables-together)
- [Output Format](#output-format)
    - [converted data (first table)](#converted-data-first-table)
        - [packages](#packages)
        - [classes](#classes)
        - [functions](#functions)
        - [variables](#variables)
        - [example code](#example-code)
    - [parser information (second table)](#parser-information-second-table)
- [Full Example](#full-example)

<!-- end toc -->

## Goals
Undoc is a lightweight file format and parser for code documentation. Unlike other code documentation tools, undoc separates the code from its documentation and produces output that is easy to convert to other formats.

undoc's goals include:

- portability (runs on any system that can run lua)
- language agnosticism
- light footprint
- human-readable input
- easy to transform output into any format desired

## Implementation
The official version of undoc is written in lua, although users are encouraged to write their own implementations if they want.

This repository should be considered the official version of undoc, and all current features in this repository should be considered the official feature set of undoc. However, if users wish to add new features in their own implementations, backwards compatibility is encouraged but not required. Users are strongly encouraged to document all changes.

## Usage
```
lua undoc.lua [INPUT FILE] (OUTPUT FILE)
```

If no output file is specified, undoc will output to `stdout`.

## Language
Note that for the purposes of these examples, all output will presented in the form of a pseudo-lua table. This approximates but does not reflect the actual output of undoc; see [output format](#output-format) for actual output.

### whitespace
Undoc ignores all whitespace, including indentation, although its use is encouraged for readability. (See [example code](#example-code) for an exception.)

### comments
Lines that start with `//` are comments. Comments are treated as blank lines during processing. Multiline comments are not allowed - use multiple single-line comments instead. Comments must take up their whole line.

### scoping
Some undoc elements can hold other elements. These elements become `children` of the element that contains them. The following types of elements can have children:

* package
* class
* function/constructor

Since undoc ignores all whitespace, it must use scoping to determine when an element becomes a child of another element. Undoc keeps track of the current scope at all times; it starts at the top of the output tree and changes throughout parsing.

All elements have a scope level; higher-level elements will always become children of lower-level elements. The current scope changes when an element with the same or lower level is encountered.

If an element is encountered with a scope level higher than the current scope, it becomes a child of the current scope. If an element is encountered with a scope level less than or equal to the current scope, the current scope changes to that element. The scope order is:

1. package
2. class
3. function, constructor
4. variable, example code

Note that this means variables and example code can never be parent elements. Similarly, descriptions always describe the current scope but are added as a property of the current scope rather than as a child, so they are not ranked on this list.

### back operator
Lines that contain nothing but a back operator (`<`) are used to exit the current scope and move up a level. Back operators on the top level are treated as whitespace.

Lines that begin with the back operator (`<`) but contain other elements act like postfix back operations; they first evaluate the rest of the line before changing scope. The processed line is then placed in this new scope.

```
[package]
   class1:
      scoped into class1

   // scope out of class1 and into package
   <
   class2:
      scoped into class2

// scope out of class2 (via class4), THEN scope out of package (via back operator)
< class4:
   scoped out of class2
```

maps to:

```
package = {
   class1 = {
      scoped into class1,
   },
   class2 = {
      scoped into class2,
   },
},
class4 = {
   scoped out of class2
},
```

By listing elements in reverse scope order, you can avoid needing to use the back operator entirely.

### includes
Lines that start with a bang (`!`) are includes. Includes allow you to import external undoc files into your current file.

File paths are written using slashes (`/`) regardless of your OS's directory separator. This makes undoc 100% portable. File paths are relative to the file that imports them.

Undoc treats imported files the same way it would if the file's contents were used instead of the import statement. The scope persists through file imports, so be careful. This also means the same file can be imported more than once.

## Elements

### packages
Packages are defined by text in surrounding brackets. They are used to specify file organization.

```
TERM WITHOUT A PACKAGE

[package] 
TERM WITH A PACKAGE 
```

maps to:

```
TERM WITHOUT A PACKAGE,
package = {
   TERM WITH A PACKAGE,
},
```

Packages are automatically split by `.` and `/`.

```
[package]
TERM 1

[package.subpackage]
TERM 2

[package/subpackage/sub2]
TERM 3
```

maps to:

```
package = {
   TERM 1,
   subpackage = {
      TERM 2,
      sub2 = {
         TERM 3,
      },
   },
}
```

You do not need to define a parent package before writing a subpackage; `[package.subpackage]` will create `package` and `package.subpackage` regardless of whether or not `[package]` was previously declared.

### classes
Class declarations start at the beginning of the line and end with a colon.

```
FUNCTIONS AND VARIABLES

class:
   CLASS FUNCTIONS AND VARIABLES
```

maps to:

```
FUNCTIONS AND VARIABLES,
class = {
   CLASS FUNCTIONS AND VARIABLES,
},
```

Classes can also derive from a parent class with arrow (`->`) notation. Note that superclasses do not need to be defined anywhere else in the document in order to be used. Classes can inherit from multiple superclasses if the superclasses are separated by commas.

```
superclass:
   CLASS FUNCTIONS AND VARIABLES

class -> superclass:
   SUBCLASS FUNCTIONS AND VARIABLES
```

maps to:

```
superclass = {
   CLASS FUNCTIONS AND VARIABLES,
},
class [superclass: {"superclass"}] = {
   SUBCLASS FUNCTIONS AND VARIABLES,
},
```

### descriptions
Descriptions start with `=` and go to the end of the line. Descriptions describe the current scope.

```
[package]
   = package description
   class:
      = class description
```

maps to:

```
package [description: {"package description"}] = {
   class [description: {"class description"}] = {},
},
```

Multiple descriptions can be applied to the same scope.

```
[package]
   = package description
   class:
      = class description 1
      = class description 2
```

maps to:

```
package [description: {"package description"}] = {
   class [description: {"class description 1", "class description 2"}] = {},
},
```

You can also create inline descriptions. Since descriptions go until the end of their lines, inline descriptions must be the last element in any given line.

```
[package] = package description
```

maps to:

```
package [description = "package description"] = {},
```

### example code
To create example code, wrap your code in double greater-than signs (`>>`).

```
>>
code
code
code
>>
```

maps to:

```
code [code: "code
             code
             code"],
```

Note that code is the only place where whitespace is not ignored. However, leading whitespace to the double greater-than sign will be stripped from all lines.

All whitespace is treated the same; this means tabs are considered just as "long" as spaces.

```
      >>
      leading whitespace is stripped
         but only until the double greater-than
      >>
```

maps to:

```
code [code: "leading whitespace is stripped
               but only until the double greater-than"],
```

Code fragments can also have titles and language declarations. To give example code a title, place it after the first double greater-than. Titles go until the end of the line. If no title is provided, `code` will be used instead.

To specify a language, place the language after the second double greater-than. Languages go until the end of the line.

```
>>title
code in a specific language
>>language
```

maps to:

```
title [code: "code in a specific language", language: "language"],
```

### functions
Functions are lines that contain parentheses and are not packages, classes, descriptions, or example code. They are written with the function name followed by parentheses.

```
function()
function with spaces & interesting characters()
```

maps to:

```
function,
function with spaces & interesting characters,
```

Functions can specify arguments by placing them within the parentheses, separated by commas.

```
function(a, b, c)
```

maps to:

```
function [arguments: {a, b, c}],
```

Functions can specify a return type via arrow (`->`) notation. To specify multiple return types, separate them with commas.

```
add(x, y) -> number
```

maps to:

```
add [arguments: {x, y}, returns: {number}],
```

#### static functions
Static functions are created by starting a function definition with a period.

```
class:
   .staticFunction() -> bool, number
```

maps to:

```
class = {
   staticFunction [scope: "static", returns: {bool, number}],
},
```

#### private
Private functions are created by starting a function definition with an asterisk.

```
class:
   *privateFunction(a, b, c)
```

maps to:

```
class = {
   privateFunction [scope: "private", arguments: {a, b, c}]
},
```

#### constructors
To create a constructor, define a function without a name.

```
class:
   (a, b)
```

maps to:

```
class = {
   constructor [arguments: {a, b}],
},
```

### variables
If a line is not a package, class, description, example code, or function, it is considered a variable.

```
line:
   point1
   point2
```

maps to:

```
line = {
   point1,
   point2,
},
```

Variables can define a type with a colon.

```
trueOrFalse:boolean
```

maps to:

```
trueOrFalse [class: "boolean"],
```

Variables can define a default value with an ampersat (`@`).

```
framesPerSecond:number @24
```

maps to:

```
framesPerSecond [class: "number", default: "24"]
```

Like functions, variables can be described as static or private with `.` and `*`. Variables can also be described as optional with a tilde. This is most useful in function definitions.

```
.staticVariable:number @1
*privateVariable:number @2
~optionalVariable:number @3
```

maps to:

```
staticVariable [scope: "static", class: "number", default: "1"],
privateVariable [scope: "private", class: "number", default: "2"],
optionalVariable [scope: "optional", class: "number", default: "3"],
```

### using functions and variables together
To describe function arguments, place variables with the same name as an argument within the function scope.

```
add(x, y) -> number
   x:number = first number to add
   y:number = second number to add
```

maps to:

```
add [arguments: {
       x [class: "number", description: "first number to add"],
       y [class: "number", description: "second number to add"],
    },
    returns: {"number"}],
```

To describe return types, place the description after an arrow (`->`). Return types are described in order. To skip one, write a line that only contains an arrow.

```
complicatedReturns() -> number, bool, string
   -> number description
   // skip bool description
   ->
   -> string description
```

maps to:

```
complicatedReturns [returns: {
                       number [description: "number description"],
                       bool,
                       string [description: "string description"],
                    }],
```

## Output Format
Undoc returns a string of lua code that returns two tables. This can be sourced into other lua programs by `loadfile` or `include`.

The first table contains the data converted from undoc's input. The second table contains information about the parser that read the data.

### converted data (first table)
Undoc data is represented as a table of ordered tables. These tables are presented in the same order as they appear in the parsed undoc document. All tables have the following properties:

**name**  
the label for the object represented by the table

**type**  
the type of object represented by the table (package, class, function, variable, code)

**description (optional)**  
a table containing every description of the object represented by the table

For instance:

```
[just a package]
```

would be represented by the table:

```
{
   name = "just a package",
   type = "package",
}
```

Different types of objects may have unique additional properties:

#### packages

**children**  
the objects that exist within this package (represented by a table of tables)

#### classes

**children**  
the objects (usually variables and functions) within this class (represented by a table of tables)

**superclass (optional)**  
table of class names this class inherits from

#### functions

**children**  
the objects owned by this function (represented by a table of tables)

**scope (optional)**  
the function scope (private or static - if the function is public, this property will not be present)

**arguments (optional)**  
a table of function arguments

if the argument is only present in the function definition but never described as a child of the function, it is represented by a string containing only its name; otherwise, it is represented as a normal variable (see below)

**returns (optional)**
a table of types the function returns

if the return is only present in the function definition but never described, it is represented by a string containing only its type; otherwise it is represented as a table containing a `type` field (string) for its type and a `description` field (string) containing its description

#### variables

**scope (optional)**  
the variable scope (private, static, or optional - if the variable is public, this property will not be present)

**class (optional)**  
the type of object represented by the variable, represented as a string containing the type name

**default (optional)**  
the default value of the variable, represented as a string

#### example code

(note that, for example code, the `name` field contains the title given to the example code)

**code**  
the code contained by the code object

**language (optional)**  
the language the code is written in

### parser information (second table)

The second table contains the following fields. Examples in parentheses are what will be returned by this version of undoc:

**name**  
the name of the parser (`undoc`)

**author**  
the name of the author of the parser (`Jonathan Stoler`)

**url**  
where to get this parser (`https://github.com/jonstoler/undoc`)

**version**  
the version of the parser, string (`1.0`)

**decimalVersion**  
the version of the parser, number (`1`)

## Full Example

```
// this is an example undoc document.
// its processed output is shown below.

// note: this example is oversimplified for brevity.

[example.geometry]
add(x, y) -> number
   = add two numbers
   x:number = the first number
   y:number = the second number
   -> the sum of the two numbers

Point:
   x:number
   y:number

   (x, y) = make a new point

Rect -> Point:
   .build() -> Rect
   
   >>create a new rectangle
   local r = Rect(0, 0, 10, 10)
   Rect.transform(r)
   >>lua
```

```
return {
   {
      ["type"] = "package",
      ["children"] = {
         {
            ["type"] = "package",
            ["children"] = {
               {
                  ["children"] = {
                  },
                  ["description"] = {
                     "add two numbers",
                  },
                  ["name"] = "add",
                  ["type"] = "function",
                  ["arguments"] = {
                     {
                        ["description"] = {
                           "the first number",
                        },
                        ["name"] = "x",
                        ["type"] = "variable",
                        ["class"] = "number",
                     },
                     {
                        ["description"] = {
                           "the second number",
                        },
                        ["name"] = "y",
                        ["type"] = "variable",
                        ["class"] = "number",
                     },
                  },
                  ["returns"] = {
                     {
                        ["type"] = "number",
                        ["description"] = "the sum of the two numbers",
                     },
                  },
               },
               {
                  ["type"] = "class",
                  ["children"] = {
                     {
                        ["type"] = "variable",
                        ["class"] = "number",
                        ["children"] = {
                        },
                        ["name"] = "x",
                     },
                     {
                        ["type"] = "variable",
                        ["class"] = "number",
                        ["children"] = {
                        },
                        ["name"] = "y",
                     },
                     {
                        ["children"] = {
                        },
                        ["description"] = {
                           "make a new point",
                        },
                        ["name"] = "constructor",
                        ["type"] = "constructor",
                        ["arguments"] = {
                           "x",
                           "y",
                        },
                     },
                  },
                  ["name"] = "Point",
               },
               {
                  ["type"] = "class",
                  ["children"] = {
                     {
                        ["children"] = {
                           {
                              ["children"] = {
                              },
                              ["name"] = "create a new rectangle",
                              ["type"] = "code",
                              ["language"] = "lua",
                              ["code"] = [[local r = Rect(0, 0, 10, 10)
Rect.transform(r)
]],
                           },
                        },
                        ["name"] = "build",
                        ["type"] = "function",
                        ["returns"] = {
                           "Rect",
                        },
                        ["scope"] = "static",
                     },
                  },
                  ["superclass"] = {
                     "Point",
                  },
                  ["name"] = "Rect",
               },
            },
            ["name"] = "geometry",
         },
      },
      ["name"] = "example",
   },
},
{
   ["url"] = "https://github.com/jonstoler/undoc",
   ["name"] = "undoc",
   ["author"] = "Jonathan Stoler",
   ["decimalVersion"] = 1,
   ["version"] = "1.0",
}
```
