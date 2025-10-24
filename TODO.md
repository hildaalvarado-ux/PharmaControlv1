# TODO: Ajustes en el Módulo Movimientos

## Información Recopilada
- **MovementsManager**: Actualmente muestra una lista filtrada de movimientos con filtros, pero no una tabla inicial con todos los registros de ingresos y egresos.
- **Dashboard**: Tiene navegación a "Movimientos", pero no muestra la vista general con tabla y botones principales.
- **IngresoFormPage**: Existe pero no funciona correctamente; necesita replicar la estructura de EgresoFormWidget, permitiendo selección de producto (existente o nuevo), categoría y proveedor.
- **EgresoFormWidget**: Funciona bien y sirve como modelo para IngresoFormPage.
- **Botones**: Necesitan texto blanco para visibilidad.
- **Integración**: Dashboard debe mostrar la vista de Movimientos con tabla inicial y botones.

## Plan de Implementación
1. **Modificar MovementsManager**:
   - Cambiar la vista inicial para mostrar una tabla con todos los registros de ingresos y egresos combinados.
   - Agregar botones principales "Egresos" e "Ingresos" que filtren la lista y permitan redirigir a EgresoFormWidget e IngresoFormPage respectivamente.
   - Asegurar que los botones tengan texto blanco (foregroundColor: Colors.white).

2. **Corregir IngresoFormPage**:
   - Replicar la estructura y formato de EgresoFormWidget.
   - Permitir selección de producto existente o crear uno nuevo.
   - Agregar selección de categoría (crear nueva si no existe).
   - Mantener selección de proveedor como en productos.

3. **Actualizar Dashboard**:
   - Asegurar que al seleccionar "Movimientos" en el menú, se muestre la vista general de MovementsManager con tabla y botones.
   - Verificar navegación correcta.

4. **Manejo de Estados Vacíos**:
   - Mostrar mensaje o estado vacío cuando no haya datos en la tabla inicial o listas filtradas.

5. **Pruebas y Validación**:
   - Probar navegación, filtros, formularios y estados vacíos.
   - Verificar integración completa.

## Pasos Detallados
- [ ] Paso 1: Modificar MovementsManager para tabla inicial con todos los registros.
- [ ] Paso 2: Agregar botones "Egresos" e "Ingresos" con navegación y texto blanco.
- [ ] Paso 3: Corregir IngresoFormPage replicando EgresoFormWidget.
- [ ] Paso 4: Agregar selección de producto, categoría y proveedor en IngresoFormPage.
- [ ] Paso 5: Actualizar Dashboard para vista correcta de Movimientos.
- [ ] Paso 6: Implementar manejo de estados vacíos.
- [ ] Paso 7: Probar y validar cambios.
