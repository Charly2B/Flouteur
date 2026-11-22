# Flouteur

Application macOS (SwiftUI) : floutez les zones d'un PDF ou d'une image (IBAN, adresse, salaire…) avant de l'envoyer, puis exportez un document masqué.

Projet perso : je crée mes propres applications pour me simplifier la vie.

## Vidéo de présentation

Aussi sur YouTube : https://youtu.be/Y0UroSCA7VM

## Ce que fait l'app

- Ouvre un PDF, même de plusieurs pages, ou une image (PNG, JPEG, HEIC, TIFF, BMP, GIF) : bouton Ouvrir ou glisser-déposer.
- Rectangles tracés à la souris, flou appliqué en direct, sur chaque page.
- Curseur d'intensité, Annuler, Effacer la page, compteur de zones.
- Recherche de texte dans un PDF : chaque occurrence surlignée sur toutes les pages, puis floutée d'un seul clic.
- Export dans le même format que la source. Le PDF exporté est aplati en image (environ 200 DPI) : le texte caché n'existe plus dans le fichier, impossible de le sélectionner ou de le copier.
- 100 % local : aucun envoi sur Internet, aucun compte, aucun abonnement.

## Construire

Ouvrir `Flouteur.xcodeproj` dans Xcode (macOS 14 ou plus récent), schéma **Flouteur**. Aucune dépendance externe (PDFKit et Core Image).

Architecture détaillée : [ARCHITECTURE.md](ARCHITECTURE.md).

## Contact

Une question, une idée ? ditel@wanadoo.fr
