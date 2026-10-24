# PlanetForm

Juego 3D en primera persona de crafteo y terraformación, hecho con Godot 4 y GDScript.
Llegas a un planeta muerto, recolectas recursos, fabricas máquinas y lo vuelves habitable.

Este es el **prototipo mínimo**: un bucle completo desde "Roca muerta" hasta "Habitable".

## Cómo abrirlo

1. Instala Godot 4.3 o posterior (versión estándar, no la .NET) desde godotengine.org.
2. En el gestor de proyectos de Godot, pulsa **Importar** y elige el archivo `project.godot` de esta carpeta.
3. Pulsa **F5** (o el botón de reproducir) para jugar.

El proyecto usa el renderizador **Compatibility** para que la misma versión funcione en el navegador.

## Controles

| Tecla | Acción |
| --- | --- |
| WASD / flechas | Moverse |
| Ratón | Mirar |
| Espacio | Saltar |
| Clic izquierdo | Usar la herramienta (y capturar el ratón) |
| 1 / 2 / 3 o rueda del ratón | Cambiar el modo de la herramienta: recoger, construir o desmontar |
| Tab o C | Abrir y cerrar el menú de crafteo (herramientas y botellas) |
| E | Abrir la taquilla o la bomba de agua que miras |
| Q | Usar una botella de oxígeno |
| H | Abrir y cerrar el menú de pausa |
| Esc | Cerrar el menú de crafteo o soltar el ratón |
| R / rueda del ratón | Girar lo que estás colocando |
| Clic derecho o Esc | Cancelar la colocación |

## Cómo se juega

- La **herramienta** de la mano tiene tres modos y su cabezal cambia con cada uno:
  - **Recoger** (taladro naranja): clic en un recurso para recogerlo o en una taquilla para abrirla.
  - **Construir** (emisor azul): abre el menú de construcción, con un icono por pieza. Al elegir una se coloca con la silueta verde o roja.
  - **Desmontar** (pinzas rojas): lo que apuntas se tiñe de rojo; con un clic se quita y te devuelve todos sus materiales.
    Una pared con puerta o ventana quita solo esa pieza; un módulo hay que vaciarlo antes de desmontarlo.
- Las **taquillas** guardan hasta 50 recursos. Al desmontar una, lo guardado vuelve a la mochila.

- Recoge **hierro** (rocas marrones), **silicio** (cristales azules), **hielo** (placas blancas) y **cobre** (rocas verdes).
- Craftea **paneles solares** para tener energía (solo de día) y **generadores de oxígeno** para subir el oxígeno del planeta.
  Cada máquina necesita un panel para funcionar al 100 %.
- El **índice** de terraformación es 40 % oxígeno + 40 % temperatura + 20 % biomasa: sin plantas se llega como mucho al 80 %.
- Al llegar al 20 % del índice se desbloquea el **calentador**, que sube la temperatura.
- Al llegar al 50 % (Deshielo) se desbloquean recetas con **cobre** (rocas verdes): turbina eólica (3 de energía),
  generador y calentador avanzados (triple de efecto, gastan 2 de energía) y el tanque de oxígeno (reserva de 200).
- **Deshielo en el mundo:** el hielo de los valles se encoge y desaparece (en las zonas altas queda una cuarta parte) y
  los lagos van subiendo poco a poco en los valles. Con el agua por encima de las rodillas andas más despacio.
- **Agua:** se recoge con un clic en la superficie de un lago (no se agota) o con una **bomba de agua** (gasta 1 de energía,
  saca 1 de agua cada 6 s, guarda hasta 20; se abre con E para sacarla).
- **Biomasa:** las **semillas de musgo** (1 agua + 1 silicio) se plantan fuera con el menú de construcción. El musgo crece
  solo, no gasta energía y sube la biomasa. El **bancal de cultivo** (con lámpara) la sube el triple pero gasta 1 de energía; va bien dentro de la base.
- **Día y noche:** un día dura 4 minutos. De noche tu **calor** baja (menos cuanto más caliente está el planeta)
  salvo si estás a menos de 8 m de un calentador con energía; de día se recupera. Si el calor llega a 0, gastas oxígeno el triple de rápido.
- **Colocar:** lo que se construye no aparece solo: una silueta sigue tu mirada, verde donde se puede construir y roja donde no
  (el motivo sale en el centro). Se paga al colocarlo, así que cancelar no cuesta nada.
- **Base:** el **módulo de hábitat** es una caja de 4 × 4 m. Si miras un módulo al colocar otro, se encaja a su lado y la pared
  común desaparece. A sus paredes se les añaden **puertas** (con rampa) y **ventanas**. Dentro de un módulo se rellena tu oxígeno
  y no pasas frío, y se pueden colocar máquinas sobre su suelo.
- Tu oxígeno baja con el tiempo; las **botellas** lo recargan. Si llega a cero, mueres.
- Al morir, la pantalla se funde a negro en 3 segundos y sale **GAME OVER**; con Enter vuelves a la base con el oxígeno y el calor al máximo.
- Etapas: Roca muerta (0 %) → Primera neblina (20 %) → Deshielo (50 %, hielo que se funde, lagos, musgo) → Habitable (100 %, aparecen árboles).

La partida se guarda sola cada 15 segundos, al cambiar de etapa, al cerrar la ventana, al perder el foco y, en el navegador, al ocultar la pestaña.
Al arrancar sale el menú principal: **Continuar partida** carga lo guardado y **Nueva partida** (pide confirmación) la borra y empieza de cero. Con **H** se abre el mismo menú como pausa.
Se guarda en `user://partida.json` (en el escritorio, la carpeta de datos de usuario de Godot; en el navegador, el almacenamiento del navegador).

Todos los sonidos (pasos, recoger, craftear, colocar, avisos, viento) se generan por código al arrancar en `scripts/sound.gd`, sin archivos de audio ni licencias. El viento sopla más fuerte de noche.

El aspecto low poly también se genera por código en `scripts/main.gd`: cielo con degradado y atardeceres, niebla que aumenta con la atmósfera, estrellas y luz de luna de noche, rocas y cristales con varias formas, y árboles y arbustos variados al llegar a Habitable.

Todas las cantidades son provisionales y están en `scripts/game_state.gd`.

## Exportar al navegador

1. En Godot: **Editor → Gestionar plantillas de exportación** y descarga las plantillas de tu versión.
2. **Proyecto → Exportar → Añadir… → Web**, y exporta a una carpeta `export/web/` con `index.html`.
3. Comprime esa carpeta en un .zip y súbela a itch.io como juego HTML.

## Versiones descargables

GitHub Actions (`.github/workflows/compilar.yml`) exporta el juego para navegador, Windows y macOS con Godot 4.7.2:

- En cada pull request las tres versiones quedan como artefacto `PlanetForm` en la ejecución del workflow.
- Al subir una etiqueta que empiece por `v` se publican en una Release de GitHub:

  ```
  git tag v0.3
  git push origin v0.3
  ```

  La versión de la app de macOS se toma de la etiqueta (`v0.3` → `0.3`).

La versión de macOS no está firmada con una cuenta de desarrollador de Apple, así que macOS la bloquea la primera vez.
Para abrirla: intenta abrirla una vez, ve a **Ajustes del Sistema → Privacidad y seguridad** y pulsa **Abrir igualmente**.

## Estructura

```
project.godot          Configuración (autoload Game, renderizador Compatibility)
scenes/main.tscn       Escena principal
scripts/game_state.gd  Estado global: inventario, recetas, métricas, etapas
scripts/main.gd        Construye el mundo: terreno low poly, recursos, agua, plantas
scripts/player.gd      Jugador en primera persona y recolección
scripts/resource_node.gd  Depósitos de recursos que reaparecen
scripts/machine.gd     Paneles, generadores y calentadores
scripts/hud.gd         Interfaz y menú de crafteo
```

El mundo se genera desde código para que el prototipo sea fácil de leer y modificar sin el editor.
