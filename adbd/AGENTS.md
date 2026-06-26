## Formatting

We uses clang-format. Run `clang-format -i src/*.c include/*.h` to format.

## Compile Command

We use bear to generate `compile_commands.json`.

## Check

- Always format the code
- Always check if compile after formation

> Formatting the code might reorder macro and cause compile to fail.
> In this case, you are writing unmaintainable macro, please fix the macro.
> You should not fix the formatter
