# Instrucciones del proyecto

## Compilar y arrancar en local

Usa siempre este comando desde la raíz del proyecto para compilar y arrancar Toolbox en local, también después de cambios y en las siguientes versiones:

```sh
./Scripts/dev.sh
```

El script verifica la firma, cierra las copias anteriores, instala en `~/Applications/Toolbox Dev.app` y abre esa misma copia. Este flujo conserva la identidad de desarrollo para que macOS mantenga el permiso de Accesibilidad entre recompilaciones.

- No sustituyas este flujo por `xcodebuild` seguido de `open`, por Run de Xcode ni por la apertura de aplicaciones desde `work/DerivedData`, `outputs` o carpetas de versiones anteriores.
- Conserva el bundle ID `com.cristian.Toolbox.debug`, la ruta de instalación y la identidad de firma persistente configurada en `Config/LocalSigning.xcconfig`.
- No uses firma ad hoc (`CODE_SIGN_IDENTITY = "-"` o `codesign --sign -`) para una app que se vaya a ejecutar. La prueba de regresión puede usarla en su copia desechable para verificar que se rechaza.
- Si falta el certificado o falla la firma, corrige la configuración con `Scripts/setup-signing.sh`; no cambies de identidad ni eludas la verificación para conseguir que arranque.
- No restablezcas permisos con `tccutil` como parte de compilaciones, arranques o actualizaciones normales. La limpieza inicial de entradas antiguas ya se realizó.

## Validación y entregas

- Para compilar sin instalar ni arrancar: `./Scripts/dev.sh --build-only`.
- Para las pruebas de la aplicación: `./Scripts/test.sh`.
- Para comprobar la continuidad de la firma entre compilaciones: `./Scripts/test-signing.sh`.
- Para generar la entrega Release: `./Scripts/build.sh`. Sus resultados son artefactos de distribución; para arrancar en desarrollo sigue usando `./Scripts/dev.sh`.
