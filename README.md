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
| Clic izquierdo | Recoger el recurso que miras (y capturar el ratón) |
| Tab o C | Abrir y cerrar el menú de crafteo |
| Q | Usar una botella de oxígeno |
| Esc | Soltar el ratón |

## Cómo se juega

- Recoge **hierro** (rocas marrones), **silicio** (cristales azules) y **hielo** (placas blancas).
- Craftea **paneles solares** para tener energía y **generadores de oxígeno** para subir el oxígeno del planeta.
  Cada máquina necesita un panel para funcionar al 100 %.
- Al llegar al 25 % del índice se desbloquea el **calentador**, que sube la temperatura.
- Tu oxígeno baja con el tiempo; las **botellas** lo recargan. Si llega a cero vuelves al punto de inicio.
- Etapas: Roca muerta (0 %) → Primera neblina (25 %) → Deshielo (60 %, aparece agua) → Habitable (100 %, aparecen plantas).

Todas las cantidades son provisionales y están en `scripts/game_state.gd`.

## Exportar al navegador

1. En Godot: **Editor → Gestionar plantillas de exportación** y descarga las plantillas de tu versión.
2. **Proyecto → Exportar → Añadir… → Web**, y exporta a una carpeta `export/web/` con `index.html`.
3. Comprime esa carpeta en un .zip y súbela a itch.io como juego HTML.

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
