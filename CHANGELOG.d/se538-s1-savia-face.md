---
bump: minor
section: Added
---

- SE-538 S1: cara 2D de Savia en Sonora (`SaviaFace`). Dos estilos JSON (buhita y círculo) más «sin cara», estados en reposo, escucha, piensa, habla y sin red, movimiento reducido con cambio estático y colores de los tokens del tema. Los estilos se validan: cualquier URL, `href`, imagen o color literal se rechaza y la cara cae a la buhita. No hace peticiones de red. «Habla» y «voz callada» se alimentan en este slice con eventos simulados; el nivel real `speech-level` llega en S2.
