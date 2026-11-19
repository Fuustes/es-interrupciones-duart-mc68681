# E/S por interrupciones con la DUART MC68681 (Motorola 68000)

Proyecto de **Arquitectura de Computadores** (ETSIINF-UPM, curso 2025-26). Implementa en **ensamblador del MC68000** la entrada/salida **no bloqueante por interrupciones** sobre la DUART MC68681:

- `INIT`: inicialización de la DUART y de los búferes circulares.
- `SCAN`: lectura no bloqueante de un bloque de caracteres.
- `PRINT`: escritura no bloqueante de un bloque de caracteres.
- `RTI`: rutina de tratamiento de interrupción, con preservación de registros y protección frente a interrupciones anidadas.

## Archivos
- `Proyecto Arqui.s`: versión final del proyecto.
- `es_int.s`: versión anterior / de pruebas.
- `MemoriaDuart.pdf`: memoria del proyecto.

Se ejecuta en el simulador BSVC (68000 + DUART).

## Autor
Mario Fustes González
