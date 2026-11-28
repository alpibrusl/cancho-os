# certs.sh OPENSSL -- in the directory it is run in: a root, and four servers' certificates (docs/tls.md): good, ended,
# for another name, and signed by a root nobody was given. Every name is made up; the keys are for the test and nothing else.
O=$1
set -e
$O ecparam -name prime256v1 -genkey -noout -out ca.key
$O req -x509 -new -key ca.key -sha256 -days 3650 -subj "/CN=probe root" -out ca.pem \
   -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
$O ecparam -name prime256v1 -genkey -noout -out other-ca.key
$O req -x509 -new -key other-ca.key -sha256 -days 3650 -subj "/CN=another root" -out other-ca.pem \
   -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
leaf() { # name cn san ca days-args...
  n=$1; san=$2; ca=$3; shift 3
  $O ecparam -name prime256v1 -genkey -noout -out $n.key
  $O req -new -key $n.key -subj "/CN=$n" -out $n.csr
  printf 'subjectAltName=DNS:%s\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n' "$san" > $n.ext
  $O x509 -req -in $n.csr -CA $ca.pem -CAkey $ca.key -CAcreateserial -sha256 -extfile $n.ext -out $n.pem "$@"
}
leaf good board.test ca -days 365
leaf ended board.test ca -not_before 20200101000000Z -not_after 20210101000000Z
leaf othername elsewhere.test ca -days 365
leaf unknown board.test other-ca -days 365
