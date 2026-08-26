# Importamos nixpkgs desde el canal configurado en nuestro sistema.
# En tu caso utilizará el canal nixpkgs que ya tienes configurado
# para Nix/Home Manager.
{ pkgs ? import <nixpkgs> {} }:

let
  # Creamos una versión de PHP específicamente para este entorno.
  #
  # "withExtensions" nos permite especificar las extensiones de PHP
  # que necesitaremos para Laravel y MariaDB.
  php = pkgs.php84.withExtensions ({ enabled, all }: enabled ++ (with all; [
    # Permite que PHP se conecte a MariaDB/MySQL mediante PDO.
    pdo_mysql

    # Manipulación de strings multibyte.
    # Laravel la utiliza para trabajar correctamente con UTF-8.
    mbstring
  ]));

  # Comandos auxiliares de MariaDB declarados como binarios.
  #
  # Se declaran con pkgs.writeShellScriptBin para que queden disponibles
  # tanto dentro de `nix-shell` como en la sesión de Bash con direnv
  # (las funciones definidas en el shellHook no se propagan vía direnv).
  #
  # Cada script deriva las rutas de MariaDB a partir de DB_DIR, con
  # fallback a "$PWD/.mariadb" si el shellHook no las exportó.
  db-start = pkgs.writeShellScriptBin "db-start" ''
    DB_DIR="''${DB_DIR:-$PWD/.mariadb}"

    DB_DATA="$DB_DIR/data"
    DB_SOCKET="$DB_DIR/mariadb.sock"
    DB_PID="$DB_DIR/mariadb.pid"
    DB_LOG="$DB_DIR/mariadb.log"

    # Evita iniciar dos instancias accidentalmente.
    if [ -f "$DB_PID" ] && kill -0 "$(cat "$DB_PID")" 2>/dev/null; then
      echo "MariaDB ya está ejecutándose."
      exit 0
    fi

    echo "Iniciando MariaDB..."

    # Si no hay un proceso activo, cualquier socket existente está obsoleto.
    rm -f "$DB_SOCKET"

    mariadbd \
      --datadir="$DB_DATA" \
      --socket="$DB_SOCKET" \
      --pid-file="$DB_PID" \
      --log-error="$DB_LOG" \
      --bind-address=127.0.0.1 \
      --port=3309 \
      &

    DB_PROCESS_PID=$!
    DB_START_ATTEMPTS=50
    DB_START_ATTEMPT=0

    while [ "$DB_START_ATTEMPT" -lt "$DB_START_ATTEMPTS" ]; do
      if [ -S "$DB_SOCKET" ]; then
        echo "MariaDB se inició correctamente en 127.0.0.1:3309."
        exit 0
      fi

      if ! kill -0 "$DB_PROCESS_PID" 2>/dev/null; then
        wait "$DB_PROCESS_PID" 2>/dev/null
        DB_EXIT_CODE=$?

        echo "MariaDB no pudo iniciarse. Log de error:"
        if [ -f "$DB_LOG" ]; then
          tail -n 20 "$DB_LOG"
        else
          echo "No se encontró el archivo de log: $DB_LOG"
        fi

        if [ "$DB_EXIT_CODE" -eq 0 ]; then
          exit 1
        fi
        exit "$DB_EXIT_CODE"
      fi

      sleep 0.1
      DB_START_ATTEMPT=$((DB_START_ATTEMPT + 1))
    done

    echo "MariaDB no creó el socket dentro del tiempo esperado. Log de error:"
    if [ -f "$DB_LOG" ]; then
      tail -n 20 "$DB_LOG"
    else
      echo "No se encontró el archivo de log: $DB_LOG"
    fi
    exit 1
  '';

  db-stop = pkgs.writeShellScriptBin "db-stop" ''
    DB_DIR="''${DB_DIR:-$PWD/.mariadb}"

    DB_DATA="$DB_DIR/data"
    DB_SOCKET="$DB_DIR/mariadb.sock"
    DB_PID="$DB_DIR/mariadb.pid"
    DB_LOG="$DB_DIR/mariadb.log"

    if [ -f "$DB_PID" ] && kill -0 "$(cat "$DB_PID")" 2>/dev/null; then
      echo "Deteniendo MariaDB..."

      mariadb-admin \
        --socket="$DB_SOCKET" \
        -u root \
        shutdown

      echo "MariaDB detenido."
    else
      echo "MariaDB no está ejecutándose."
    fi
  '';

  db-shell = pkgs.writeShellScriptBin "db-shell" ''
    DB_DIR="''${DB_DIR:-$PWD/.mariadb}"

    DB_DATA="$DB_DIR/data"
    DB_SOCKET="$DB_DIR/mariadb.sock"
    DB_PID="$DB_DIR/mariadb.pid"
    DB_LOG="$DB_DIR/mariadb.log"

    mariadb \
      --socket="$DB_SOCKET" \
      -u root
  '';

in

# mkShell crea un entorno de desarrollo.
# Los paquetes declarados aquí estarán disponibles únicamente
# mientras estemos dentro de `nix-shell`.
pkgs.mkShell {

  packages = [
    # PHP con las extensiones configuradas arriba.
    php

    # Composer utiliza el mismo PHP que definimos anteriormente.
    php.packages.composer

    # Node.js para React, Vite y las herramientas frontend.
    # npm viene incluido con Node.js.
    pkgs.nodejs_22

    # Gestor de paquetes.
    pkgs.pnpm_11

    # Servidor y cliente de MariaDB.
    pkgs.mariadb

    # Comandos auxiliares de MariaDB (db-start, db-stop, db-shell).
    db-start
    db-stop
    db-shell
  ];


  # ------------------------------------------------------------------
  # Variables de MariaDB
  # ------------------------------------------------------------------

  # Este código se ejecuta automáticamente cada vez que ejecutemos:
  #
  #     nix-shell
  #
  shellHook = ''
    # Directorio donde guardaremos todo lo relacionado con
    # nuestra instancia LOCAL de MariaDB.
    export DB_DIR="$PWD/.mariadb"

    # Aquí MariaDB almacenará físicamente las tablas y bases de datos.
    #
    # Como está dentro del proyecto, los datos sobreviven al salir
    # de nix-shell y volver a entrar posteriormente.
    export DB_DATA="$DB_DIR/data"

    # Socket Unix utilizado por MariaDB.
    export DB_SOCKET="$DB_DIR/mariadb.sock"

    # Archivo donde MariaDB guardará el PID del proceso.
    export DB_PID="$DB_DIR/mariadb.pid"

    # Log de nuestra instancia local de MariaDB.
    export DB_LOG="$DB_DIR/mariadb.log"

    ## Laravel instalador
    export PATH="$HOME/.composer/vendor/bin:$HOME/.config/composer/vendor/bin:$PATH"

    # --------------------------------------------------------------
    # Crear directorios
    # --------------------------------------------------------------

    mkdir -p "$DB_DIR"


    # --------------------------------------------------------------
    # Inicialización de MariaDB
    # --------------------------------------------------------------
    #
    # Solamente se ejecuta la PRIMERA vez.
    #
    # Si $DB_DATA/mysql ya existe significa que MariaDB ya fue
    # inicializado anteriormente y NO se modifica la base de datos.
    #
    # Esto es lo que nos proporciona persistencia entre sesiones.
    if [ ! -d "$DB_DATA/mysql" ]; then
      echo ""
      echo "Inicializando MariaDB por primera vez..."

      mkdir -p "$DB_DATA"

      mariadb-install-db \
        --datadir="$DB_DATA" \
        --auth-root-authentication-method=normal

      echo "MariaDB inicializado."
    fi


    # --------------------------------------------------------------
    # Mensaje mostrado al entrar al entorno
    # --------------------------------------------------------------

    echo ""
    echo "========================================"
    echo " Laravel + React development environment"
    echo "========================================"
    echo ""
    echo "PHP:      $(php --version | head -n 1)"
    echo "Composer: $(composer --version 2>/dev/null)"
    echo "Node:     $(node --version)"
    echo "pnpm:      $(pnpm --version)"
    echo "MariaDB:  $(mariadb --version)"
    echo ""
    echo "Comandos disponibles:"
    echo ""
    echo "  db-start    Iniciar MariaDB"
    echo "  db-stop     Detener MariaDB"
    echo "  db-shell    Abrir consola MariaDB"
    echo ""
  '';
}
