# FRC Language Support — Guía de instalación

Extensión de VS Code que proporciona resaltado de sintaxis, autocompletado y diagnósticos en tiempo real para el lenguaje FRC (archivos `.fr`).

---

## Prerrequisitos

| Herramienta        | Versión mínima |
| ------------------ | -------------- |
| Node.js            | 18.x           |
| npm                | 9.x            |
| Visual Studio Code | 1.85           |

---

## 1. Instalar dependencias

Desde la raíz del repositorio:

```bash
cd vscode-frc
npm install
```

---

## 2. Compilar la extensión

```bash
npm run compile
```

Esto transpila `src/extension.ts` a `out/extension.js`. El directorio `out/` debe existir tras este paso.

Para recompilar automáticamente al modificar el código fuente:

```bash
npm run watch
```

---

## 3. Cargar la extensión en VS Code

### Opción A — Entorno de desarrollo (recomendado para pruebas)

1. Abre la carpeta `vscode-frc/` en VS Code:
   ```bash
   code vscode-frc/
   ```
2. Presiona **F5** (o ve a *Run → Start Debugging*).

Se abrirá una segunda ventana de VS Code llamada **Extension Development Host** con la extensión activa. Cualquier archivo `.fr` que se abra en esa ventana tendrá soporte completo.

### Opción B — Instalación permanente sin publicar

Copiar (o crear un enlace simbólico) el directorio compilado en la carpeta de extensiones de VS Code:

```bash
# `npm run compile` debe ejecutarse previamente
ln -s "$(pwd)/vscode-frc" ~/.vscode/extensions/frc-language-0.0.1
```

Reiniciar VS Code. Con ello, la extensión estará disponible en todas las ventanas.

> **Nota:** el enlace simbólico apunta al directorio de trabajo, por lo que
> cualquier `npm run compile` posterior se refleja sin necesidad de reinstalar.

---

## 4. Configurar la ruta al compilador

Los diagnósticos en tiempo real requieren que VS Code pueda invocar el compilador FRC. Abrir la configuración de VS Code (**Ctrl+,** → `frc`) y establecer:

| Ajuste                 | Valor                        | Descripción                                               |
| ---------------------- | ---------------------------- | --------------------------------------------------------- |
| `frc.compilerPath`     | `/ruta/absoluta/al/repo/frc` | Ruta al script `frc` en la raíz del repositorio           |
| `frc.diagnosticsDelay` | `800` (por defecto)          | Milisegundos de espera antes de re-validar tras un cambio |

O bien, editar `settings.json` directamente:

```json
{
  "frc.compilerPath": "/home/usuario/ISA_PROJECT/frc"
}
```

> Sin `frc.compilerPath` el resaltado de sintaxis y el autocompletado funcionan; solo los diagnósticos quedan desactivados.

---

## 5. Verificar el funcionamiento

Abrir cualquier archivo `.fr` en VS Code. Debería poder observarse:

- **Resaltado de sintaxis**: palabras clave, tipos, literales y comentarios
  coloreados según el tema activo.
- **Autocompletado**: sugerencias al escribir (o con **Ctrl+Space**) para
  palabras clave, snippets y símbolos declarados en el archivo.
- **Diagnósticos**: subrayado ondulado rojo en errores léxicos, sintácticos o
  semánticos (requiere `frc.compilerPath` configurado).
