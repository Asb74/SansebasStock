# Sansebas Stock

Aplicación Flutter conectada a Firebase para la gestión de stock.

## Configuración del proyecto

1. Instala las dependencias de Flutter:
   ```bash
   flutter pub get
   ```
2. Configura los ficheros de Firebase (`google-services.json`, `GoogleService-Info.plist`, etc.) para cada plataforma.
3. Inicia sesión en Firebase CLI y selecciona el proyecto correspondiente:
   ```bash
   firebase login
   firebase use <tu-proyecto>
   ```

## Reglas e índices de Firestore

El repositorio incluye las reglas e índices mínimos para Firestore en la carpeta `firebase/`.

- Reglas: `firebase/firestore.rules`
- Índices: `firebase/firestore.indexes.json`

Después de realizar cambios en estos ficheros, despliega la configuración con los siguientes comandos:

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

## Ejecución en desarrollo

Lanza la aplicación en un dispositivo o emulador:

```bash
flutter run
```

Utiliza `flutter test` para ejecutar la batería de pruebas cuando sea necesario.
