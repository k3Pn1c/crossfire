#!/bin/bash

# Colores para mejorar la legibilidad
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
display_banner() {
    echo -e "${BLUE}"
    echo "
   █████████                                     ███████████  ███                    
  ███░░░░░███                                   ░░███░░░░░░█ ░░░                     
 ███     ░░░  ████████   ██████   █████   █████  ░███   █ ░  ████  ████████   ██████ 
░███         ░░███░░███ ███░░███ ███░░   ███░░   ░███████   ░░███ ░░███░░███ ███░░███
░███          ░███ ░░░ ░███ ░███░░█████ ░░█████  ░███░░░█    ░███  ░███ ░░░ ░███████ 
░░███     ███ ░███     ░███ ░███ ░░░░███ ░░░░███ ░███  ░     ░███  ░███     ░███░░░  
 ░░█████████  █████    ░░██████  ██████  ██████  █████       █████ █████    ░░██████ 
  ░░░░░░░░░  ░░░░░      ░░░░░░  ░░░░░░  ░░░░░░  ░░░░░       ░░░░░ ░░░░░      ░░░░░░  
                                                                                     
      "
    echo -e "${NC}"
    echo -e "${YELLOW}Version: 1.0${NC}"
    echo -e "${YELLOW}Author: Jose Miguel Romero (aka. k3Pn1c${NC})"
    echo -e "${BLUE}##########################################${NC}"
    echo ""
}

# Ayuda
show_help() {
    echo -e "${YELLOW}"
    echo "Usage: ./crossfire.sh [OPTIONS]"
    echo "Options:"
    echo "  -h          Show this help message."
    echo "  -u <url>    Scan a single URL."
    echo "  -w <file>   Scan multiple URLs from a file."
    echo "  -o <origin> Set a custom origin (default: https://evil.com)."
    echo "  -t <threads> Set the number of concurrent threads (default: 10)."
    echo "  -s <file>   Save results to a file."
    echo -e "${NC}"
}

# Variables globales
THREADS=10
ORIGIN="https://evil.com"
OUTPUT_FILE=""
URL_LIST=()

# Función para verificar CORS básico
check_basic_cors() {
    local url=$1
    local response=$(curl -s -I -H "Origin: $ORIGIN" "$url")
    local cors_header=$(echo "$response" | grep -i 'Access-Control-Allow-Origin')
    local credentials_header=$(echo "$response" | grep -i 'Access-Control-Allow-Credentials')

    if [[ -n "$cors_header" ]]; then
        if [[ "$cors_header" =~ \* ]]; then
            echo -e "${RED}[!] $url: Vulnerable to CORS - Wildcard (*) in Access-Control-Allow-Origin${NC}"
        elif [[ "$cors_header" =~ "$ORIGIN" ]]; then
            echo -e "${RED}[!] $url: Vulnerable to CORS - Origin reflection in Access-Control-Allow-Origin${NC}"
        else
            echo -e "${GREEN}[+] $url: CORS header present, but no obvious misconfiguration detected${NC}"
        fi

        if [[ "$credentials_header" =~ "true" ]]; then
            echo -e "${RED}[!] $url: Access-Control-Allow-Credentials is set to true${NC}"
        fi
    else
        echo -e "${GREEN}[+] $url: No CORS headers detected${NC}"
    fi
}

# Función para verificar métodos HTTP permitidos
check_allowed_methods() {
    local url=$1
    local response=$(curl -s -I -X OPTIONS -H "Origin: $ORIGIN" "$url")
    local methods_header=$(echo "$response" | grep -i 'Access-Control-Allow-Methods')

    if [[ -n "$methods_header" ]]; then
        if [[ "$methods_header" =~ (PUT|DELETE) ]]; then
            echo -e "${RED}[!] $url: Unsafe HTTP methods allowed (PUT/DELETE)${NC}"
        else
            echo -e "${GREEN}[+] $url: Safe HTTP methods allowed${NC}"
        fi
    else
        echo -e "${YELLOW}[-] $url: No Access-Control-Allow-Methods header found${NC}"
    fi
}

# Función para verificar headers permitidos
check_allowed_headers() {
    local url=$1
    local response=$(curl -s -I -X OPTIONS -H "Origin: $ORIGIN" "$url")
    local headers_header=$(echo "$response" | grep -i 'Access-Control-Allow-Headers')

    if [[ -n "$headers_header" ]]; then
        if [[ "$headers_header" =~ \* ]]; then
            echo -e "${RED}[!] $url: All headers allowed (wildcard detected)${NC}"
        else
            echo -e "${GREEN}[+] $url: Specific headers allowed, no wildcard detected${NC}"
        fi
    else
        echo -e "${YELLOW}[-] $url: No Access-Control-Allow-Headers header found${NC}"
    fi
}

# Función principal para escanear una URL
scan_url() {
    local url=$1
    echo -e "${BLUE}[*] Scanning $url${NC}"
    check_basic_cors "$url"
    check_allowed_methods "$url"
    check_allowed_headers "$url"
    echo ""
}

# Exportar funciones para uso con xargs
export -f scan_url check_basic_cors check_allowed_methods check_allowed_headers
export ORIGIN RED GREEN YELLOW BLUE NC

# Procesar argumentos
while getopts "hu:w:o:t:s:" opt; do
    case $opt in
        h)
            show_help
            exit 0
            ;;
        u)
            URL_LIST+=("$OPTARG")
            ;;
        w)
            if [[ -f "$OPTARG" ]]; then
                mapfile -t URL_LIST < "$OPTARG"
            else
                echo -e "${RED}Error: File $OPTARG not found.${NC}"
                exit 1
            fi
            ;;
        o)
            ORIGIN="$OPTARG"
            ;;
        t)
            THREADS="$OPTARG"
            ;;
        s)
            OUTPUT_FILE="$OPTARG"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

# Validar entradas
if [[ ${#URL_LIST[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No URLs provided. Use -u or -w.${NC}"
    exit 1
fi

# Mostrar banner
display_banner

# Escanear URLs
for url in "${URL_LIST[@]}"; do
    if [[ -n "$OUTPUT_FILE" ]]; then
        scan_url "$url" | tee -a "$OUTPUT_FILE"
    else
        scan_url "$url"
    fi
done

# Escanear en paralelo si hay muchas URLs
if [[ ${#URL_LIST[@]} -gt 1 ]]; then
    echo -e "${BLUE}[*] Running scans in parallel with $THREADS threads...${NC}"
    printf "%s\n" "${URL_LIST[@]}" | xargs -P "$THREADS" -n 1 -I {} bash -c 'scan_url "$@"' _ {}
fi

echo -e "${GREEN}[+] Scan completed.${NC}"