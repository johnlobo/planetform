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
| Espacio | Saltar (mantenido en el aire, con propulsores: volar un poco) |
| Clic izquierdo | Usar la herramienta (y capturar el ratón) |
| 1 / 2 / 3 o rueda del ratón | Cambiar el modo de la herramienta: recoger, construir o desmontar |
| Tab o C | Abrir y cerrar el menú de fabricar y construir (vuelve a la última pestaña usada) |
| E | Abrir la taquilla, la bomba de agua, el bancal, el extractor o la estación de drones que miras; dormir en la cama; usar el terminal o el telepuerto; abrir una caja de suministros; subir al róver y bajar de él |
| L | Encender y apagar la linterna |
| W S / A D (en el róver) | Acelerar y frenar o marcha atrás / girar; Espacio es el freno |
| Q | Usar una botella de oxígeno |
| F | Comer (verduras, raciones o guiso) |
| Esc | Cerrar el menú, la taquilla o la colocación que tengas abierta; si no hay nada abierto, pausa (y suelta el ratón) |
| R / rueda del ratón | Girar lo que estás colocando |
| Clic derecho o Esc | Cancelar la colocación |

## Cómo se juega

- **Fabricar y construir** comparten un menú: una sola lista con cuatro secciones separadas por un título, un icono por receta y la rueda para bajar si no cabe. En **Fabricar** están las herramientas, las botellas, las semillas, el guiso y los componentes: van al inventario y el menú sigue abierto para hacer más. Lo que se coloca en el mundo está repartido en **Construcción** (base, muebles, pantallas), **Tecnología** (energía, vehículos, automatización) y **Terraformación** (lo que sube las métricas del planeta): al elegirlo, la herramienta pasa a modo construir y empieza la colocación. Tab abre el menú arriba; el modo construir, en Construcción. Solo sale lo desbloqueado; lo demás no se enseña.

- **Materiales avanzados y sitios recónditos** (a partir de 250 m de la base):
  - **Cuevas** (48 en el mapa, en laderas de montaña): una sala de roca gruesa metida en la montaña, con un túnel de entrada de roca maciza. La entrada mira siempre cuesta abajo y se llega por una rampa; desde arriba o de lado solo se ven las rocas de la loma, así que hay que rodearla hasta encontrar la entrada. Dentro no llueve y está oscuro (fabrica la **linterna**, L). Tienen **titanio** en las paredes, **cuarzo** rosa al fondo y, en la mitad, una caja de suministros.
  - **Restos de naves** (18, desde 300 m): cada uno con una caja de suministros.
  - **Cráteres** (14, desde 600 m): el terreno se hunde 6 m hacia el centro, con el borde levantado y rocas alrededor, y un meteorito de **iridio** en el fondo.
  - El titanio y el cuarzo piden el taladro mejorado; el iridio, el térmico. Tardan 5 minutos en reaparecer.
  - Con titanio se fabrica la **placa de aleación** (2 titanio + 1 hierro) y con cuarzo el **circuito** (1 cuarzo + 1 cobre + 1 silicio); aparecen en Fabricar al recoger el material por primera vez.
- **Desbloqueos.** Cada caja de suministros se abre una vez y da un **chip de datos** o un **fragmento de plano**. Las tecnologías avanzadas se desbloquean así:

  | Tecnología | Pestaña | Qué hace | Coste | Se desbloquea con |
  |---|---|---|---|---|
  | Generador geotérmico | Tecnología | +6 de energía, de día y de noche | 4 hierro, 2 placas, 2 circuitos | 2 chips (terminal) |
  | Telepuerto | Tecnología | E para ir al siguiente telepuerto (gasta 1 de energía) | 3 placas, 3 circuitos, 2 iridio | 3 fragmentos |
  | Extractor de titanio | Tecnología | Saca titanio de un depósito de una cueva | 3 placas, 2 circuitos | 4 chips (terminal) |
  | Liberador de gases de efecto invernadero | Terraformación | Temperatura x6, gasta 3 de energía | 3 placas, 2 circuitos | Índice 35 % |
  | Torre atmosférica | Terraformación | Presión x6, gasta 3 de energía | 4 placas, 2 circuitos, 1 iridio | 3 fragmentos |
  | Árbol modificado | Terraformación | Biomasa x5 y oxígeno x2, sin energía | 2 semillas, 2 agua, 1 circuito | Lluvias y 3 chips (terminal) |

  Los chips se gastan en el **terminal de investigación** (Construcción): E sobre él para ver qué se puede investigar. Los planos a medias salen arriba a la derecha. El extractor automático normal no saca materiales avanzados.

- La **herramienta** de la mano tiene tres modos y su cabezal cambia con cada uno:
  - **Recoger** (taladro): mantén pulsado el clic sobre un recurso hasta que se llene la barra bajo la mira y lo recoges entero
    (un depósito tiene 3), o haz clic en una taquilla para abrirla.
- **Taladros:** cada uno se fabrica en la pestaña Fabricar, necesita el anterior y cambia el color de la broca.

  | Taladro | Etapa | Coste | Segundos de barra | Recoges |
  |---|---|---|---|---|
  | Básico (naranja) | al empezar | — | 1,0 | x1 (3 por depósito) |
  | Mejorado (plateado) | Roca muerta | 3 hierro, 1 silicio | 0,7 | x2 (6) |
  | Térmico (rojo) | Deshielo | 4 hierro, 3 cobre, 2 silicio | 0,45 | x2 (6) |
  | De plasma (violeta) | Lluvias | 5 hierro, 4 cobre, 3 silicio, 2 agua | 0,25 | x3 (9) |
  - **Construir** (emisor azul): abre el menú en la pestaña Construir. Al elegir una pieza se coloca con la silueta verde o roja.
  - **Desmontar** (pinzas rojas): lo que apuntas se tiñe de rojo; con un clic se quita y te devuelve todos sus materiales.
    Una pared con puerta o ventana quita solo esa pieza; un módulo hay que vaciarlo antes de desmontarlo.
- Las **taquillas** guardan hasta 50 recursos. Al desmontar una, lo guardado vuelve a la mochila.

- Recoge **hierro** (rocas marrones), **silicio** (cristales azules), **hielo** (placas blancas) y **cobre** (rocas verdes).
- Craftea **paneles solares** para tener energía (solo de día) y **generadores de oxígeno** para subir el oxígeno del planeta.
  Cada máquina necesita un panel para funcionar al 100 %.
- La **perforadora de gases** (gasta 1 de energía) sube la **presión** del planeta; con más presión la niebla es más densa.
- El **índice** de terraformación es 30 % oxígeno + 30 % temperatura + 20 % presión + 20 % biomasa: sin plantas se llega como mucho al 80 %.
  En una partida guardada antes de que hubiera presión, esta empieza con el valor que deja el índice igual que antes.
- **Pantallas:** la **pantalla de terraformación** muestra el índice, la etapa, cuánto falta para la siguiente y una barra por métrica.
  Los **monitores** de oxígeno, calor, presión y biomasa muestran una sola métrica en grande y cuánto sube por minuto. No gastan energía
  y se pueden poner dentro de la base.
- Al llegar al 20 % del índice se desbloquea el **calentador**, que sube la temperatura.
- Al llegar al 50 % (Deshielo) se desbloquean recetas con **cobre** (rocas verdes): turbina eólica (3 de energía),
  generador y calentador avanzados y el **compresor atmosférico** (triple de efecto, gastan 2 de energía) y el tanque de oxígeno (reserva de 200).
- **Deshielo en el mundo:** el hielo de los valles se encoge y desaparece (en las zonas altas queda una cuarta parte) y
  los lagos van subiendo poco a poco en los valles. Con el agua por encima de las rodillas andas más despacio.
- **Agua:** se recoge manteniendo el clic sobre la superficie de un lago (no se agota) o con una **bomba de agua** (gasta 1 de energía,
  saca 1 de agua cada 6 s, guarda hasta 20; se abre con E para sacarla).
- **Propulsores** (Primera neblina, se fabrican con Tab): con Espacio pulsado en el aire empujan hacia arriba unos 3 s
  (unos 20 m de subida) y dejan ir más rápido; se rellenan solos al pisar el suelo. Sirven para subir a las montañas.
- **Róver de exploración** (Primera neblina): se coloca desde la pestaña Construir. E para subir y bajar.
  Tiene un **maletero** de 20 unidades (clic en modo recoger) y una **batería** que se gasta al acelerar (unos 2 minutos
  de acelerador). Se recarga aparcado a menos de 6 m de un **punto de recarga**, que gasta 1 de energía.
  Al desmontarlo, lo del maletero vuelve a la mochila.
- **Estación de drones** (Deshielo, gasta 2 de energía): sus dos drones van solos al depósito libre más cercano
  (hasta 70 m), recogen 1 unidad y la traen a la estación, que guarda hasta 30. Se abre con E para sacarlo.
  Sin energía se quedan en sus plataformas.
- **Biomasa:** las **semillas de musgo** (1 agua + 1 silicio) se plantan fuera con el menú de construcción. El musgo crece
  solo, no gasta energía y sube la biomasa. El **bancal de cultivo** (con lámpara) la sube el triple pero gasta 1 de energía; va bien dentro de la base.
- **Comida y hambre:** la barra de **comida** se vacía en 12 minutos (tres días), también dentro de la base. Con **F** comes:
  primero verduras (+20), luego raciones (+40) y luego guiso (+100). Si la barra llega a 0 tienes 60 segundos para comer o te desmayas.
  Empiezas con 5 **raciones de emergencia**. El **bancal de cultivo** da 1 de **verduras** cada 20 s con toda la energía (guarda hasta 12;
  se ven los frutos rojos y se abre con E para sacarlas). Con 3 verduras + 1 agua se fabrica un **guiso**, que llena la barra entera.
- **Día y noche:** un día dura 4 minutos. De noche tu **calor** baja (menos cuanto más caliente está el planeta)
  salvo si estás a menos de 8 m de un calentador con energía; de día se recupera. Si el calor llega a 0, gastas oxígeno el triple de rápido.
- **Colocar:** lo que se construye no aparece solo: una silueta sigue tu mirada, verde donde se puede construir y roja donde no
  (el motivo sale en el centro). Se paga al colocarlo, así que cancelar no cuesta nada.
- **Base:** el **módulo de hábitat** es una caja de 4 × 4 m. Si miras un módulo al colocar otro, se encaja a su lado y la pared
  común desaparece. A sus paredes se les añaden **puertas** (con rampa) y **ventanas**. Dentro de un módulo se rellena tu oxígeno
  y no pasas frío, y se pueden colocar máquinas sobre su suelo.
- **Pasillos** (recto 3 hierro + 1 silicio; en L y en T 4 hierro + 1 silicio): ocupan una casilla de 4 × 4 m como un módulo
  pero son un tubo de 2,5 m de ancho que solo sale por sus bocas. Al colocarlos junto a un módulo se giran solos para que una boca
  mire hacia él (R cambia a la siguiente posición que encaje); el módulo deja un hueco del ancho del pasillo. Las bocas libres se
  cierran con una pared a la que se le puede poner una puerta o una ventana pequeña; las paredes laterales del cuadrado del
  centro también admiten puerta o ventana.
- **En altura:** mirando el techo de un módulo de hábitat se coloca otro encima (otra planta, sin zócalo). Junto a una planta
  de arriba se pueden encajar pasillos y módulos aunque queden en el aire, como un puente. Un módulo con otro encima no se
  desmonta hasta quitar el de arriba.
- **Escalera** (2 hierro): se coloca mirando un módulo de hábitat y va siempre en su esquina, con una trampilla en el techo que
  sale al tejado o a la planta de arriba. En la escalera, W o Espacio suben y S baja.
- **Techos:** en el techo de los módulos se pueden poner paneles solares, turbinas y otras máquinas de fuera (no plantas).
  Un módulo con algo en el techo no se desmonta hasta quitarlo. Los paneles solares van ahora sobre un soporte.
- **Luces de la base:** las de los módulos y pasillos solo se encienden si se produce energía o hay batería cargada.
- **Cuestas:** si el terreno sobresale por encima del suelo de un módulo, se excava al colocarlo (hasta 3 m); por debajo, el zócalo
  llega hasta 3,5 m. Las máquinas en una cuesta de más de 0,7 m se ponen a la altura de su esquina más baja y también se excava
  lo que sobra. Lo excavado se guarda con la partida y no vuelve aunque se desmonte lo construido.
- **Cama** (3 hierro): va dentro de la base. Con E o clic duermes hasta el amanecer si es de noche (pasa algo de hambre) y desde
  entonces reapareces en ella al morir.
- **Farola** (1 hierro + 1 silicio): lleva su placa solar, no gasta energía y se enciende sola de noche.
- **Extractor automático** (Primera neblina, 5 hierro + 2 silicio): se coloca mirando un depósito y saca su recurso sin agotarlo,
  1 cada 15 s con energía (gasta 1) hasta 15 guardados; se vacía con E.
- **Batería** (Primera neblina, 3 hierro + 3 cobre + 1 silicio): guarda la energía que sobra (hasta 2 por segundo) y la da cuando falta,
  por ejemplo de noche. Cada una guarda lo justo para tener 1 de energía durante una noche entera. La carga sale en la esquina.
- Tu oxígeno baja con el tiempo; las **botellas** lo recargan. Si llega a cero, mueres.
- Al morir, la pantalla se funde a negro en 3 segundos y sale **GAME OVER**; con Enter vuelves a la base con el oxígeno, el calor y la comida al máximo.
- **Lluvias** (75 %): aparecen nubes, el cielo se vuelve azul y los bosques del mapa empiezan a crecer. Cada 3 minutos de juego cae
  un chubasco de unos 50 s (gotas, cielo gris, más niebla y sonido de lluvia). Mientras llueve, el musgo y los árboles suben la biomasa
  el doble de rápido. Construcciones nuevas:
  - **Colector de lluvia** (2 hierro + 2 silicio): no gasta energía; solo con lluvia saca 1 de agua cada 5 s y guarda hasta 20 (E para abrirlo).
  - **Plantón de árbol** (2 semillas + 2 agua): se planta fuera, crece en 90 s y sube la biomasa (el doble que el musgo) y algo de oxígeno.
  - **Criadero de insectos** (3 hierro + 2 cobre + 2 verduras): gasta 1 de energía, sube la biomasa y los bancales a menos de 10 m dan
    verduras un 50 % más rápido.
  Una partida guardada antes de que existieran las Lluvias que ya estaba en Habitable sigue en Habitable.
- Etapas: Roca muerta (0 %) → Primera neblina (20 %) → Deshielo (50 %, hielo que se funde, lagos, musgo) → Lluvias (75 %, nubes, lluvia, bosques) → Habitable (100 %).

La partida se guarda sola cada 15 segundos, al cambiar de etapa, al cerrar la ventana, al perder el foco y, en el navegador, al ocultar la pestaña.
Al arrancar sale el menú principal: **Continuar partida** carga lo guardado y **Nueva partida** (pide confirmación) la borra y empieza de cero. Con **Esc** se abre el mismo menú como pausa, siempre que no haya otro menú abierto (entonces Esc solo lo cierra).
Se guarda en `user://partida.json` (en el escritorio, la carpeta de datos de usuario de Godot; en el navegador, el almacenamiento del navegador).

Todos los sonidos (pasos, recoger, craftear, colocar, avisos, viento, lluvia) se generan por código al arrancar en `scripts/sound.gd`, sin archivos de audio ni licencias. El viento sopla más fuerte de noche.

El aspecto low poly también se genera por código en `scripts/main.gd`: cielo con degradado y atardeceres, niebla que aumenta con la atmósfera, estrellas y luz de luna de noche, rocas y cristales con varias formas, nubes, lluvia y árboles y arbustos variados al llegar a las Lluvias.

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
scripts/main.gd        Construye el mundo: cielo, agua, recursos y la base
scripts/terrain.gd     Terreno de 2 km por trozos: montañas, rocas, árboles y recursos de cada zona
scripts/player.gd      Jugador en primera persona y recolección
scripts/resource_node.gd  Depósitos de recursos que reaparecen
scripts/machine.gd     Máquinas, taquillas y pantallas
scripts/hud.gd         Interfaz y menú de fabricar y construir
scripts/icons.gd       Iconos del menú, dibujados en el juego
```

El mundo se genera desde código para que el prototipo sea fácil de leer y modificar sin el editor.
