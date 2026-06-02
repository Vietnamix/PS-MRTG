# PS-MRTG — MRTG Bandwidth Monitor

> Moniteur de bande passante réseau en temps réel, façon **MRTG**, écrit en **PowerShell**.
> Interface web interactive, 100 % offline, sans installation ni service.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D6?logo=windows&logoColor=white)
![Chart.js](https://img.shields.io/badge/Chart.js-4.4.0-FF6384?logo=chartdotjs&logoColor=white)
![Mode](https://img.shields.io/badge/ConstrainedLanguage-compatible-success)
![Version](https://img.shields.io/badge/version-1.16-blue)
![License](https://img.shields.io/badge/license-MIT-green)

PS-MRTG sonde les compteurs réseau de Windows et affiche, en direct dans votre
navigateur, les débits **entrant (IN)** et **sortant (OUT)** de chaque interface,
sur 4 échelles de temps (de la dernière heure aux 15 derniers jours).

---

## ✨ Fonctionnalités

- **Temps réel** : rafraîchissement automatique toutes les 2 secondes.
- **4 vues temporelles agrégées** par interface : Live (1 h), 6 h, 2,5 j, 15 j.
- **Vue « Tous »** : les 4 fenêtres côte à côte dans une grille 2×2, plus un mode plein écran par vue.
- **Débit IN / OUT** tracé en courbes lissées (Chart.js).
- **Échelle Y automatique** par paliers fins 1‑2‑5 (10 / 20 / 50 / 100 / 200 / 500 Mbps … jusqu'à 200 Gbps), ou **échelle fixe** au choix.
- **Seuil d'alarme** (ligne rouge) optionnel, qui ajuste l'échelle pour rester visible. Désactivé par défaut.
- **Axe temporel exact** : un historique partiel n'occupe que sa portion réelle du graphe (1 jour de données sur la vue 15 j = 1/15ᵉ de la largeur), avec graduations régulières (6 segments par graphe).
- **Thème clair / sombre**.
- **Export snapshot** de la vue Live.
- **100 % offline** : aucune dépendance réseau une fois Chart.js déposé localement.
- **Compatible ConstrainedLanguage** (environnements verrouillés) — PowerShell 5.1 et 7+.

---

## 📸 Aperçu

<p align="center">
  <img src="docs/PS_MRTG_2026-06-02 180418.png" alt="Vue Live plein écran" width="48%">
</p>

---

## 🧩 Les 4 vues temporelles

Chaque vue conserve 720 points ; le « recul » est la fenêtre couverte une fois le tampon plein.

| Vue   | Résolution (1 point =) | Calcul du recul                       | Recul    |
|-------|------------------------|---------------------------------------|----------|
| Live  | 5 s (brut)             | 720 × 5 s = 3 600 s                    | **1 h**  |
| Hour  | 30 s (moy. 6 pts)      | 720 × 30 s = 21 600 s = 360 min       | **6 h**  |
| Day   | 5 min (moy. 60 pts)    | 720 × 5 min = 3 600 min = 60 h        | **2,5 j**|
| Week  | 30 min (moy. 360 pts)  | 720 × 30 min = 21 600 min = 360 h     | **15 j** |

---

## ✅ Prérequis

- **Windows** 10 / 11 ou Windows Server.
- **PowerShell 5.1** (intégré à Windows) ou **PowerShell 7+**.
- Un navigateur récent : **Microsoft Edge** ou **Google Chrome** recommandés.
- **Chart.js 4.4.0** (`chart.umd.min.js`) — voir l'installation ci‑dessous.

> Les compteurs sont lus via `Get-NetAdapterStatistics` (avec repli sur d'autres méthodes). Aucun droit administrateur n'est requis dans la plupart des cas.

---

## 📥 Installation

1. **Cloner le dépôt** (ou télécharger le `.ps1`) :

   ```powershell
   git clone https://github.com/votre-utilisateur/ps-mrtg.git
   cd ps-mrtg
   ```

2. **Fournir Chart.js en local** (recommandé pour le mode offline).
   Téléchargez `chart.umd.min.js` depuis le CDN officiel :

   ```
   https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js
   ```

   Renommez‑le `chartjs.min.js` et placez‑le dans l'un de ces emplacements (le script les cherche dans cet ordre) :

   ```
   %TEMP%\PSMrtg\chartjs.min.js
   %USERPROFILE%\Documents\chartjs.min.js
   %USERPROFILE%\Desktop\chartjs.min.js
   ```

   > Si le fichier est introuvable, le script tente de le télécharger automatiquement, puis se rabat en dernier recours sur le CDN (ce qui nécessite alors une connexion Internet).

---

## ▶️ Utilisation

Lancez simplement le script :

```powershell
.\PS-MRTG_v1.16.ps1
```

Le script :
1. détecte les interfaces réseau actives ;
2. génère le tableau de bord HTML et le fichier de données dans `%TEMP%\PSMrtg\` ;
3. ouvre automatiquement le navigateur sur le tableau de bord ;
4. met à jour les données toutes les 2 secondes.

**Arrêt** : `Ctrl + C` dans la console PowerShell.

> **Politique d'exécution** — si le script est bloqué, autorisez‑le pour la session courante :
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\PS-MRTG_v1.16.ps1
> ```
> Lancé depuis l'ISE, le script se relance tout seul dans `powershell.exe`.

---

## ⚙️ Configuration

Les paramètres se règlent en tête du script :

| Variable               | Défaut   | Rôle                                                        |
|------------------------|----------|-------------------------------------------------------------|
| `$IntervalSec`         | `5`      | Intervalle de collecte des compteurs (secondes).           |
| `$WriteEvery`          | `2`      | Fréquence d'écriture des données pour le navigateur (s).    |
| `$MaxPoints`           | `720`    | Nombre de points conservés par vue.                         |
| `$YScaleMode`          | `"auto"` | `"auto"` (paliers) ou une valeur fixe en Mbps (ex. `1000`). |
| `$ThresholdAlertMbps`  | `150`    | Valeur pré‑remplie du seuil d'alarme (Mbps).                |
| `$ThresholdEnabled`    | `$false` | Seuil actif au démarrage (`$true` = ligne rouge visible).   |

Les réglages **Thème**, **Échelle Y**, **Seuil** et **Taille des points** sont aussi modifiables en direct depuis l'interface.

---

## 🏗️ Fonctionnement

```
┌────────────────────┐     écrit toutes les 2 s     ┌──────────────────────┐
│  PowerShell         │ ───────────────────────────► │  network_data.js      │
│  (collecte /5 s)    │                              │  (dans %TEMP%\PSMrtg) │
└────────────────────┘                              └───────────┬──────────┘
                                                                │ recharge /2 s
                                                                ▼
                                                    ┌──────────────────────┐
                                                    │  dashboard.html        │
                                                    │  + Chart.js (offline) │
                                                    └──────────────────────┘
```

- PowerShell lit les compteurs réseau toutes les **5 s**, calcule les débits, agrège les 4 vues.
- Il écrit `network_data.js` toutes les **2 s**.
- Le navigateur recharge ce fichier toutes les **2 s** et redessine les graphiques.

### Fichiers générés (dans `%TEMP%\PSMrtg\`)

| Fichier             | Contenu                                  |
|---------------------|------------------------------------------|
| `dashboard.html`    | Le tableau de bord (HTML + JS + Chart.js).|
| `network_data.js`   | Les données de débit, réécrites en continu.|
| `mrtg_cmd.js`       | Canal de commandes léger UI → script.    |
| `chartjs.min.js`    | Copie locale de Chart.js (si déposée).   |

---

## 🖥️ Le tableau de bord

- **Sélecteur d'interface** : choisissez la carte réseau à observer.
- **Onglets de vue** : `Live · 1h (5s)`, `6h (30s)`, `2.5j (5min)`, `15j (30min)`, plus la vue **Tous**.
- **Échelle Y** : Auto (paliers) ou valeur fixe (10 Mbps → 200 Gbps).
- **Seuil** : cochez la case et saisissez une valeur en Mbps pour afficher la ligne d'alarme.
- **Thème** : bascule clair / sombre.
- **Snapshot** : exporte la vue Live.

---

## 🩺 Dépannage

- **Aucune interface détectée** : vérifiez que `Get-NetAdapterStatistics` fonctionne (`Get-NetAdapterStatistics` en console). Certaines interfaces virtuelles n'exposent pas de compteurs.
- **Graphiques vides / « Chart is not defined »** : `chartjs.min.js` n'a pas été trouvé localement et aucune connexion n'est disponible. Déposez le fichier dans `%TEMP%\PSMrtg\`.
- **Le navigateur ne s'ouvre pas** : ouvrez manuellement `%TEMP%\PSMrtg\dashboard.html`.
- **Script bloqué au lancement** : utilisez `-ExecutionPolicy Bypass` (voir plus haut).

---

## 🤝 Contribuer

Les contributions sont les bienvenues !

1. Forkez le dépôt.
2. Créez une branche : `git checkout -b feature/ma-fonctionnalite`.
3. Committez : `git commit -m "Ajout de ma fonctionnalité"`.
4. Poussez : `git push origin feature/ma-fonctionnalite`.
5. Ouvrez une Pull Request.

Merci de décrire clairement le comportement attendu et l'environnement testé (version de PowerShell, Windows, navigateur).

---

## 📝 Changelog (extraits récents)

- **v1.16** — Axe X divisé en 6 segments égaux (10 min en Live, 1 h / 10 h / 60 h selon la vue).
- **v1.15** — Axe X à domaine temporel fixe : les données s'affichent à leur position réelle.
- **v1.14** — Affichage du recul (période couverte) à côté de chaque graphique.
- **v1.13 / v1.12** — Dates sur l'axe des temps (lisibilité des vues multi‑jours).
- **v1.11** — Heures à la même taille que les débits.
- **v1.10** — Paliers d'échelle plus fins (200 / 500 Mbps…), seuil désactivé par défaut.
- **v1.9** — Échelle commune aux 4 vues, lisibilité de l'axe Y, seuil intégré à l'échelle.

---

## 📄 Licence

Distribué sous licence **MIT**. Voir le fichier [`LICENSE`](LICENSE).

> *À confirmer : si vous préférez une autre licence (Apache‑2.0, GPL‑3.0…), adaptez ce paragraphe et ajoutez le fichier `LICENSE` correspondant.*

---

## 👤 Auteur

**Eric Guiffault**

Si ce projet vous est utile, pensez à me laisser une ⭐ sur GitHub !
