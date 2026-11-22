# IKEA Browser for ConstructCraft

A ConstructCraft plugin (Plugin API 3) that adds an **IKEA** tab to the **Component Library** window, backed by the [`T-K-233/ikea-furniture`](https://huggingface.co/datasets/T-K-233/ikea-furniture) Hugging Face dataset (36,447 verified GLB models, 18,614 cached product photos).

## Features

- Instant client-side search by product name, type, variant, or article number (`000.697.68` / `00069768`).
- Category, color, and dimension (W × D × H) filters.
- Lazy thumbnail loading and SHA-256 verified, content-addressed GLB model caching.
- Automatic BIM classification (`Furniture`, `Casework`, `Plumbing`, `Lighting`) and IFC property set (`Pset_IkeaProduct`) including a clickable link to the IKEA product page for current pricing and availability.

## Attribution & Copyright

Product names, images, and 3D models originate from IKEA. This plugin and the upstream dataset do not grant a new license to IKEA's assets; check each product's IKEA website link for official product details.
