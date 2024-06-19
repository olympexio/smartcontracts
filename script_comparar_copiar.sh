#!/bin/bash

# Directorios de origen y destino
dir_origen="olympex-public-smartcontracts-cidcd"
dir_destino="smartcontracts"

# Archivo que contiene la lista de archivos/directorios excluidos
archivo_exclusion="archivo_exclusion.txt"


# Verificar si los directorios existen
if [ ! -d "$dir_origen" ]; then
    echo "El directorio origen '$dir_origen' no existe."
    exit 1
fi

if [ ! -d "$dir_destino" ]; then
    echo "El directorio destino '$dir_destino' no existe."
    exit 1
fi

# Función para verificar si un archivo debe ser excluido
archivo_debe_excluir() {
    local archivo="$1"
    while IFS= read -r linea || [[ -n "$linea" ]]; do
        # Verificar si el archivo coincide con el patrón de exclusión
        if [[ "$archivo" == "$linea" ]]; then
            return 0  # Devolver 0 si el archivo debe ser excluido
        fi
    done < "$archivo_exclusion"
    return 1  # Devolver 1 si el archivo no debe ser excluido
}

# Función para sincronizar archivos de origen a destino
sincronizar_directorios() {
    local dir_origen="$1"
    local dir_destino="$2"

    # Iterar sobre los archivos en el directorio origen
    find "$dir_origen" -type f -not -path '*/.git/*' -print0 | while IFS= read -r -d '' archivo_origen; do
        archivo_nombre=$(basename "$archivo_origen")
        archivo_destino="$dir_destino/$archivo_nombre"

        # Verificar si el archivo debe ser excluido
        if archivo_debe_excluir "$archivo_nombre"; then
            echo "El archivo '$archivo_nombre' está excluido de la sincronización."
            continue  # Saltar a la siguiente iteración del bucle
        fi

        # Verificar si el archivo existe en el directorio destino y si su contenido es diferente
        if [ -f "$archivo_destino" ]; then
            if ! cmp -s "$archivo_origen" "$archivo_destino"; then
                echo "El archivo '$archivo_nombre' en destino tiene contenido diferente. Sobrescribiendo..."
                cp "$archivo_origen" "$archivo_destino"
            fi
        else
            echo "Copiando nuevo archivo '$archivo_nombre' a destino..."
            cp "$archivo_origen" "$archivo_destino"
        fi

    done

    # Eliminar archivos en destino que ya no existen en origen
    find "$dir_destino" -type f -not -path '*/.git/*' -print0 | while IFS= read -r -d '' archivo_destino; do
        archivo_nombre=$(basename "$archivo_destino")
        archivo_origen="$dir_origen/$archivo_nombre"

        # Verificar si el archivo no existe en el directorio origen
        if [ ! -f "$archivo_origen" ]; then
            echo "El archivo '$archivo_nombre' ya no existe en origen. Eliminando..."
            rm "$archivo_destino"
        fi

    done
}

# Ejecutar la función para sincronizar los directorios
sincronizar_directorios "$dir_origen" "$dir_destino"
