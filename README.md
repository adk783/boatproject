# Ocean Navigator
*Projet réalisé à trois : Antoine Dupuy, Leonardo Dib, Raphaël Ducournau*

## Répartition de l'équipe
Pour ce projet, nous avons divisé les différentes parties :

* **Antoine Dupuy :** Développement de la physique avancée (flottabilité, traînée) et logique de navigation.
* **Raphaël Ducournau :** Création de l'aspect visuel de l'eau, des vagues et des shaders.
* **Leonardo Dib :** Level Design, gestion du brouillard et implémentation des ennemis (requins et krakens).

## Détails techniques Antoine Dupuy
J'ai implémenté :

* **Simulation de Flottabilité (`buoy.gd`) :** Système de points d'ancrage synchronisé avec les vagues.
* **Physique des Fluides (`boat_buoyancy.gd`) :** Modèle de traînée directionnelle (Drag) sur 3 axes.
* **Algèbre Vectorielle :** Stabilisation et calculs de couples pour le comportement du navire.
