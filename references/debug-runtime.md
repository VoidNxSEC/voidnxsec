#!/bin/bash
# Ativa no shebang ou inline:
set -euxo pipefail
# -e → sai no primeiro erro
# -u → erro em variáveis não definidas
# -x → imprime cada comando antes de executar (TRACE)
# -o pipefail → captura erros em pipes
