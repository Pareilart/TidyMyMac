#!/bin/sh
# Crée une identité de signature locale « TidyMyMac Local » dans le trousseau de session.
#
# Pourquoi : signée « ad hoc », l'app change d'empreinte à chaque compilation et macOS oublie
# les autorisations accordées (accès complet au disque, Automatisation…). Signée avec une identité
# stable, elle les garde d'une compilation et d'une version à l'autre. build.sh utilise cette
# identité automatiquement si elle existe.
#
# À lancer une seule fois. macOS demande le mot de passe de session pour approuver le certificat.
# Pour l'annuler : supprimez « TidyMyMac Local » dans Trousseaux d'accès.
set -e

NAME="TidyMyMac Local"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "L'identité « $NAME » existe déjà."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout pass:tidymymac

security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P tidymymac -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$WORK/cert.pem"

echo "Identité « $NAME » créée. Recompilez avec ./build.sh, puis accordez une dernière fois"
echo "l'accès complet au disque à TidyMyMac : il sera conservé lors des compilations suivantes."
