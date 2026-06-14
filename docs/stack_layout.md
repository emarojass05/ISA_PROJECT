# Convención de Stack y Dirección de Símbolos

## 1. Inicialización del puntero de pila

Al iniciar el programa, el prólogo del punto de entrada (`ENTRY`) establece:

```
sp = 0x3FFFC
```

Este valor corresponde al último byte de la memoria de datos, que tiene capacidad para 65 536 palabras de 32 bits (palabras 0 a 65 535, bytes `0x00000` a `0x3FFFC`).

---

## 2. Crecimiento del stack

El stack **crece hacia abajo**. Cada llamada a función resta `frame_size` bytes al puntero de pila:

```
addi sp, sp, -<frame_size>
```

Tras esta instrucción, `sp` apunta a la **base** del frame de la función actual.

---

## 3. Layout del frame de activación

El frame de cada función ocupa `frame_size` bytes contiguos encima de `sp`:

```
sp + 0x0000 : ra guardado  (4 bytes, no aparece en la tabla de simbolos)
sp + 0x0004 : primer parametro o variable local
sp + 0x0008 : segundo parametro o variable local
   ...
sp + 0x???? : ultima variable local
```

Los arrays locales ocupan `size * 4` bytes consecutivos a partir de su offset.
El elemento `arr@(i)` se almacena en `sp + offset_arr + i * 4`.

---

## 4. Columna "Offset/Addr" en la tabla de simbolos (-m)

La salida de `./frc -m` muestra la tabla de simbolos con dos columnas clave:

| Columna      | Simbolos locales                | Simbolos globales          |
|--------------|---------------------------------|----------------------------|
| Offset/Addr  | `sp+0xNNNN` (offset desde sp)  | `0xNNNN` (byte address absoluto) |
| Word in dump | indice de palabra en dump (*)  | `address / 4` (exacto)     |

---

## 5. Como localizar un simbolo en memory_dump.txt

`memory_dump.txt` esta indexado por **indice de palabra** (0-based), donde la palabra N corresponde al byte `N * 4`.

### Simbolos globales

```
word_index = address / 4
```

Ejemplo: simbolo global con `address = 0x0100` -> palabra 64.

### Simbolos locales

La direccion absoluta de un simbolo local depende del valor de `sp` en el momento de la llamada:

```
byte_address = sp_en_llamada - frame_size + offset
word_index   = byte_address / 4
```

Para una funcion llamada **directamente desde ENTRY** (primer nivel de call stack):

```
sp_en_llamada = 0x3FFFC
byte_address  = 0x3FFFC - frame_size + offset
word_index    = (0x3FFFC - frame_size + offset) / 4
```

La columna `Word in dump` de `./frc -m` calcula este valor asumiendo primer nivel de call stack. Para llamadas anidadas, sumar el `frame_size / 4` acumulado de cada caller.

---

## 6. Ejemplo: programa con variables locales

Considerando el siguiente programa:

```
fonc [int] main() {
    int a = 2026;
    [int] *list(10);
    int res = 42;
    ...
}
```

El compilador asigna estos offsets (`frame_size = 52` bytes):

| Simbolo | Offset (sp+N) | Byte address       | Palabra en dump |
|---------|---------------|--------------------|-----------------|
| ra      | sp+0x0000     | 0x3FFFC - 52 + 0   | 65522           |
| a       | sp+0x0004     | 0x3FFFC - 52 + 4   | 65523           |
| list    | sp+0x0008     | 0x3FFFC - 52 + 8   | 65524..65533    |
| res     | sp+0x0030     | 0x3FFFC - 52 + 48  | 65534           |

Para verificar: `(262140 - 52 + 4) / 4 = 262092 / 4 = 65523` -> palabra 65523 en el dump contiene el valor de `a`.

---

## 7. Por que el stack crece hacia abajo

El stack crece hacia abajo para separar naturalmente el espacio de datos estaticos (globales, que crecen desde `0x100` hacia arriba) del stack de llamadas (que crece desde `0x3FFFC` hacia abajo). Esto permite que ambas regiones coexistan sin colisionar mientras el programa no supere la capacidad de la memoria.
