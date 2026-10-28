extends Area3D
## Superficie de los lagos que aparecen con el Deshielo. El rayo de la
## herramienta la detecta para recoger agua, que no se agota.

const AMOUNT := 1

var resource_type := "agua"


func get_hint() -> String:
	return "Agua · mantén clic para recoger"


# El taladro multiplica lo recogido, como en los depósitos.
func harvest(multiplier: int) -> int:
	return AMOUNT * multiplier
