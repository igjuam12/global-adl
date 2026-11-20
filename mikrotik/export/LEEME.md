# export/

Lo que devuelve `/export show-sensitive` en el router real, como respaldo y evidencia:

- `isp-router-etapa1.rsc`: después de importar solo `01-base-pppoe.rsc`.
- `isp-router-completo.rsc`: después de importar los tres archivos (así queda el router terminado).

Para armar un router nuevo se usan los archivos numerados de la carpeta `mikrotik/`, no estos. Dos motivos:

- **`/export` no incluye los usuarios del router.** El usuario `btest` no aparece acá; lo crea `01-base-pppoe.rsc`.
- **La línea `/port set 0 name=serial0`** aparece porque la VM donde se tomaron tiene un puerto serie agregado. En un CHR sin puerto serie no está y no hace falta.
