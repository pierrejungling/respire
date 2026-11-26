# Respire

Petite application macOS de barre des menus qui pilote le logo Apple lumineux du MacBook Pro.

## Modes

| Mode | Effet |
|---|---|
| **Respiration** | le logo respire en continu, au rythme choisi (un seul réveil par inspiration ou expiration) |
| **Fixe** | luminosité choisie, figée |
| **macOS** | comportement d'origine d'Apple |
| **Éteint** | logo coupé (réglage persistant, comme la commande Terminal d'Apple) |

Options :

- **Allumer capot fermé** : le logo ne s'allume que si le Mac est éveillé (en pratique avec un écran externe). Il s'éteint si le Mac ou l'écran se met en veille, ou si macOS signale une chauffe élevée.
- **Sur batterie : comportement d'origine** : Respire rend la main à macOS.

## Compatibilité

- macOS 14 ou plus récent.
- Un MacBook Pro dont le logo est lumineux et pilotable. Développée et utilisée sur le MacBook Pro Apple silicon de l'auteur ; non testée sur d'autres modèles. Sur un Mac sans l'API nécessaire, l'application affiche « API du logo introuvable ».

> Respire s'appuie sur une **API privée** d'Apple (CoreBrightness). Une mise à jour de macOS peut la casser, et elle ne serait pas acceptée sur l'App Store.

## Installer sur un nouveau Mac

1. Installer les outils de développement Apple (une seule fois, gratuit ; Xcode complet inutile) :

```bash
xcode-select --install
```

2. Récupérer le projet :

```bash
git clone https://github.com/pierrejungling/Respire.git
```

3. Construire, installer dans Applications et lancer :

```bash
cd Respire && ./install.sh
```

4. Facultatif, ouverture au démarrage : **Réglages Système > Général > Ouverture et extensions**, bouton « + », choisir Respire.

L'application est compilée sur le Mac qui l'utilise et signée localement : aucun compte développeur n'est nécessaire.

## Mettre à jour

```bash
git pull && ./install.sh
```

## Désinstaller

Choisir « Quitter Respire » dans son menu, la retirer des éléments d'ouverture, puis mettre `Respire.app` à la corbeille.

## Structure

| Chemin | Rôle |
|---|---|
| `Sources/Respire/RespireApp.swift` | menu et réglages |
| `Sources/Respire/Engine.swift` | modes, respiration, veille, capot, batterie |
| `Sources/Respire/LightEmitter.swift` | accès à la LED du logo (CoreBrightness) |
| `Sources/Respire/SystemMonitor.swift` | capot, écrans externes, batterie, chauffe |
| `build.sh`, `install.sh` | construction et installation |

## Tests manuels

1. Capot ouvert, mode Respiration : le logo respire (le regarder dans un miroir ou le filmer).
2. Changer la durée et les luminosités min/max : l'effet suit.
3. Mode Fixe : le logo suit le curseur puis se fige.
4. Capot fermé avec écran externe et secteur : le logo reste allumé.
5. Mettre l'écran externe ou le Mac en veille : le logo s'éteint, puis revient au réveil.
6. Capot fermé sans écran externe : le Mac se met en veille, logo éteint.
7. Quitter l'application : le logo revient au comportement de macOS.

## En cas de souci

État brut de la LED :

```bash
ioreg -r -n bklb-backlight@0 | grep -E '"(enabled|high-period|low-period)"'
```

Si le logo reste éteint après des essais :

```bash
sudo defaults delete com.apple.CoreBrightness LEBacklightMode
```

## Crédit

Les clés et comportements de CoreBrightness utilisés ici sont documentés par le projet [LogoLight](https://github.com/Ark0N/LogoLight) (MIT).
