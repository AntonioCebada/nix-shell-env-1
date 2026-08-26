# Dashboard para empresas de TeamJobs

## Índice

- [Entorno de desarrollo](#entorno-de-desarrollo)
- [Requisitos previos](#requisitos-previos)
  - [Direnv](#direnv)
- [Estructura del entorno](#estructura-del-entorno)
- [Primer levantamiento del proyecto](#primer-levantamiento-del-proyecto)
  - [1. Clonar el repositorio](#1-clonar-el-repositorio)
  - [2. Primer levantamiento](#2-primer-levantamiento)
  - [3. Inicialización automática de MariaDB](#3-inicialización-automática-de-mariadb)
- [Dependencias JavaScript](#dependencias-javascript)
- [Comprobar que MariaDB está funcionando](#comprobar-que-mariadb-está-funcionando)
- [Archivos que sí deben almacenarse en Git](#archivos-que-sí-deben-almacenarse-en-git)

## Entorno de desarrollo

Este proyecto utiliza **Nix** para proporcionar un entorno de desarrollo reproducible con las herramientas necesarias para trabajar con:

- Laravel
- PHP
- Composer
- Node.js
- pnpm
- MariaDB

La idea es que las herramientas del entorno estén disponibles únicamente dentro de `nix-shell`, mientras que las dependencias propias del proyecto se mantienen dentro del repositorio:

- Dependencias PHP → `vendor/`
- Dependencias JavaScript → `node_modules/`
- Base de datos MariaDB local → `.mariadb/`

Esto evita depender de instalaciones globales de PHP, Composer, Node.js, pnpm o MariaDB en el sistema operativo.

> [!NOTE]
> Varios comandos usan bash como shell, por defecto solo funciona para Linux, MacOS
> o en su defecto WSL en Windows. Comprobar compatibilidad con powershell u otro shell.

---

## Requisitos previos

La computadora únicamente necesita tener:

- Nix
- Git

No es necesario instalar manualmente PHP, Composer, Node.js, pnpm ni MariaDB.
Para comprobar que Nix está instalado:

```bash
nix --version
```

Y para comprobar que `nix-shell` está disponible:

```bash
nix-shell --version
```

### Direnv

Opcionalmente se puede instalar `direnv` para que el entorno se levante automaticamente cada que se acceda al directorio del proyecto, esto evita levantarlo manualmente y ayuda sobre todo a agentes de IA.
Los requisitos para esto son:

- Tener instalado Home Manager (instalable una vez se tiene nix)

Una vez se tenga home-manager basta editar `home.nix` y agregar esto:

```nix
  programs.direnv = {   #Activa entornos shell.nix al entrar al directorio
    enable = true;

    # Integra direnv con la shell.
    enableBashIntegration = true;

    # Hace que los entornos Nix carguen más rápido
    # y sean persistentes entre entradas al directorio.
    nix-direnv.enable = true;
  };
```

Despues se ejecuta:

```bash
home-manager switch
```

---

## Estructura del entorno

El archivo `shell.nix` proporciona las herramientas necesarias para trabajar con el proyecto. De forma conceptual, la estructura queda así:

```text
Nix
├── PHP
├── Composer
├── Node.js
├── pnpm
├── MariaDB

Proyecto
├── vendor/
├── node_modules/
├── pnpm-lock.yaml
└── .mariadb/
```

Nix instala físicamente los paquetes dentro de `/nix/store`, pero no los agrega al perfil global del usuario. Las herramientas estarán disponibles mientras la terminal se encuentre dentro de nix-shell o del directorio en caso de usar direnv.

---

## Primer levantamiento del proyecto

Esta sección describe todo lo necesario cuando el proyecto se clona por primera vez.

### 1. Clonar el repositorio

```bash
git clone <URL_DEL_REPOSITORIO>
cd <NOMBRE_DEL_PROYECTO>
```

### 2. Primer levantamiento

Por default direnv no modifica nada sin tu consentimiento, para permitirle instalar las dependencias automáticamente ejecuta en la terminal:

```bash
direnv allow
```

Nix resolverá e instalará automáticamente las herramientas declaradas en `shell.nix`. Ahora deberías poder ver las versiones de los paquetes:

```text
PHP
Composer
Node
pnpm
MariaDB
```

También estarán disponibles los comandos:

```text
db-start
db-stop
db-shell
```

### 3. Inicialización automática de MariaDB

Despues de ejecutar direnv se inicializará la carpeta de MariaDB como `./.mariadb/data/` pero no inicializa aun MariaDB como tal, para ello hay que ejecutar `db-start`, este comando:

1. Comprueba que no haya una instancia del proyecto activa.
2. Elimina cualquier socket obsoleto.
3. Inicia MariaDB en 127.0.0.1:3309.
4. Espera hasta 5 segundos por .mariadb/mariadb.sock.
5. Si aparece, informa que arrancó correctamente.
6. Si MariaDB termina o vence el tiempo, muestra las últimas 20 líneas de .mariadb/mariadb.log y devuelve error.

Los datos se almacenan dentro de:

```text
.mariadb/data/
```

Por lo tanto, las bases de datos sobreviven aunque:

- Se salga del directorio
- Se cierre la terminal
- Se reinicie la computadora

Mientras `.mariadb/` no sea eliminado, los datos locales seguirán disponibles.

---

## Dependencias JavaScript

Este entorno ocupa pnpm en vez de npm, por lo que las dependencias y sus versiones estarán en `pnpm-lock.yaml`, para instalar las dependencias hay que usar:

```bash
pnpm install
```

---

## Comprobar que MariaDB está funcionando

Se puede entrar a la consola con:

```bash
db-shell
```

Esto equivale a conectarse como:

```text
usuario: root
password: vacío
```

Debería aparecer:

```text
MariaDB [(none)]>
```

---

## Archivos que sí deben almacenarse en Git

Es importante conservar:

```text
composer.json
composer.lock
package.json
pnpm-lock.yaml
shell.nix
.env.example
.envrc
```

Especialmente:

```text
composer.lock
pnpm-lock.yaml
```

Estos archivos permiten mantener versiones consistentes de las dependencias.
