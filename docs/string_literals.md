# Literales de Cadena (`[char] *name = "...";`)

## Sintaxis

```frc
[char] *nombre = "texto";
```

Declara un arreglo de tipo `[char]` e inicializa cada elemento con el valor ASCII del carácter correspondiente de la cadena. El tamaño del arreglo se deduce automáticamente de la longitud del literal.

## Secuencias de escape soportadas

| Secuencia | Valor ASCII |
|-----------|-------------|
| `\n`      | 10          |
| `\t`      | 9           |
| `\r`      | 13          |
| `\\`      | 92          |
| `\"`      | 34          |
| `\0`      | 0           |

## Ejemplo

```frc
fonc [int] main([void])
{
    [char] *greeting = "hello";
    ret greeting@(0);   $ retorna 104 ('h')
}
```

## Restricciones

- Los literales de cadena **solo** pueden aparecer en la declaración de un arreglo `[char] *`.
- Usar un literal de cadena como expresión genera un error de compilación:

  ```
  String literals are not supported as expressions.
  Declare a [char] array instead: [char] *name = "...";
  ```

- El acceso a elementos fuera del rango del arreglo no se verifica en tiempo de compilación.

## Implementación

El compilador convierte el literal en tiempo de compilación (`_parse_string_literal` en `main.py`) y emite una instrucción de escritura por carácter:

- **O0 (AsmGenerator):** `emit_load_immediate` + `emit_sp_store` para arreglos locales, o `sw` con dirección absoluta para globales.
- **O1/O2 (IRCodeGenerator):** `IRStore(base, offset, str(ascii_val))` por cada carácter.
