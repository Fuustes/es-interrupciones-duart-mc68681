*******************************************************************************
* Proyecto de Entrada/Salida mediante interrupciones
*
* Subrutinas implementadas:
*   INIT  - Inicializacion de la DUART MC68681
*   SCAN  - Lectura no bloqueante de un bloque de caracteres
*   PRINT - Escritura no bloqueante de un bloque de caracteres
*   RTI   - Rutina de tratamiento de interrupcion
*******************************************************************************

*******************************************************************************
* CONSTANTES - Direcciones de los registros de la DUART MC68681
*******************************************************************************

* Linea A
MR1A    EQU     $EFFC01         * Registro de modo 1 linea A (tambien MR2A)
CSRA    EQU     $EFFC03         * Registro seleccion de reloj linea A
CRA     EQU     $EFFC05         * Registro de control linea A
RBATBA  EQU     $EFFC07         * Buffer recepcion (lectura) / transmision (escritura) A

* Registro auxiliar y comunes
ACR     EQU     $EFFC09         * Registro de control auxiliar
ISRIMR  EQU     $EFFC0B         * ISR (lectura) / IMR (escritura)

* Linea B
MR1B    EQU     $EFFC11         * Registro de modo 1 linea B (tambien MR2B)
CSRB    EQU     $EFFC13         * Registro seleccion de reloj linea B
CRB     EQU     $EFFC15         * Registro de control linea B
RBBTBB  EQU     $EFFC17         * Buffer recepcion (lectura) / transmision (escritura) B

* Vector de interrupcion
IVR     EQU     $EFFC19         * Registro del vector de interrupcion

*******************************************************************************
* CONSTANTES - Valores de configuracion
*******************************************************************************

* MR1: 8 bits por caracter, RxRDY (interrupcion por cada caracter recibido)
* bits 1:0 = 11 -> 8 bits por caracter
* bit 6    =  0 -> RxRDY (interrupcion al recibir cada caracter)
MR1_VAL EQU     $03             * 00000011

* MR2: modo normal (full-duplex), sin eco
* bits 7:6 = 00 -> Normal
MR2_VAL EQU     $07             * 00000111 -> 1 bit stop, normal

* CSRA/CSRB: 38400 baudios transmision y recepcion
* ACR bit7=0 (conjunto 1), codigo 1100 -> 38400 en Tx y Rx
* bits 7:4 = 1100 (Rx), bits 3:0 = 1100 (Tx)
CSR_VAL EQU     $CC             * 38400 baudios Tx y Rx

* ACR: seleccion conjunto 1 de velocidades (bit 7 = 0)
ACR_VAL EQU     $00

* CRA/CRB: habilitar transmision y recepcion
* bits 3:2 = 01 -> Habilitar Tx
* bits 1:0 = 01 -> Habilitar Rx
CR_VAL  EQU     $05             * 00000101

* CRA/CRB: reinicializar puntero MR a MR1
* bits 6:4 = 001 -> Reinicializar puntero a MR1
CR_RST  EQU     $10             * 00010000

* Vector de interrupcion que suministrara la DUART
VECT    EQU     $40             * Vector 64 decimal

* Mascara IMR: habilitar RxRDY linea A (bit 2) y RxRDY linea B (bit 5)
* Bit 2: RxRDY/FFULL linea A
* Bit 5: RxRDY/FFULL linea B
* Tx NO se habilita aqui; se activara desde PRINT cuando haya datos
IMR_RX  EQU     $24             * 00100100

* Bits del ISR para identificar fuente de interrupcion
ISR_TxA EQU     $01             * Bit 0: TxRDY linea A
ISR_RxA EQU     $04             * Bit 2: RxRDY linea A
ISR_TxB EQU     $10             * Bit 4: TxRDY linea B
ISR_RxB EQU     $20             * Bit 5: RxRDY linea B

* Bits IMR para Tx (para activar/desactivar desde PRINT y RTI)
IMR_TxA EQU     $01             * Bit 0: TxRDY linea A
IMR_TxB EQU     $10             * Bit 4: TxRDY linea B

* Descriptores de buffer (para LEECAR/ESCCAR)
BUF_RxA EQU     0               * Buffer recepcion linea A
BUF_RxB EQU     1               * Buffer recepcion linea B
BUF_TxA EQU     2               * Buffer transmision linea A
BUF_TxB EQU     3               * Buffer transmision linea B

*******************************************************************************
* TABLA DE VECTORES DE EXCEPCION
* El MC68000 requiere SSP inicial en 0x000000 y PC inicial en 0x000004
*******************************************************************************

        ORG     $0
        DC.L    $007FFF         * SSP inicial (pila en zona alta de RAM 32KB)
        DC.L    INICIO          * PC inicial: comienzo del programa principal

*******************************************************************************
* CODIGO: a partir de 0x400 segun especificacion
*******************************************************************************

        ORG     $400

*******************************************************************************
* PROGRAMA PRINCIPAL DE PRUEBA
* Lee bloques de TAMBS caracteres de la linea A y los escribe en la linea B
*******************************************************************************

* Constantes del programa principal
DESA    EQU     0               * Descriptor linea A
DESB    EQU     1               * Descriptor linea B
TAMBS   EQU     30              * Tamano de bloque para SCAN
TAMBP   EQU     7               * Tamano de bloque para PRINT

INICIO:
        * Instalar manejadores de excepciones
        MOVE.L  #BUS_ERR,8      * Bus error handler
        MOVE.L  #ADDR_ERR,12    * Address error handler
        MOVE.L  #ILL_INST,16    * Illegal instruction handler
        MOVE.L  #PRIV_VIO,32    * Privilege violation handler
        MOVE.L  #ILL_INST,40    * Emulador coprocesador 1010
        MOVE.L  #ILL_INST,44    * Emulador coprocesador 1111

        * Inicializar dispositivos
        BSR     INIT
        BREAK


        * Habilitar interrupciones (nivel 0, modo supervisor)
        MOVE.W  #$2000,SR

* --- Bucle principal ---
BUCPR:
        MOVE.W  #TAMBS,PARTAM   * Inicializar tamano para SCAN
        MOVE.L  #BUFFER,PARDIR  * Inicializar direccion de lectura

* --- Bucle de lectura: leer TAMBS caracteres de linea A ---
OTRAL:
        MOVE.W  PARTAM,-(A7)    * Parametro: tamano
        MOVE.W  #DESA,-(A7)     * Parametro: descriptor linea A
        MOVE.L  PARDIR,-(A7)    * Parametro: direccion buffer
        BSR     SCAN
        ADD.L   #8,A7           * Limpiar pila (4+2+2 bytes)
        TST.L   D0
        BEQ     OTRAL           * Si D0=0, no se leyo nada, reintentar
        ADD.L   D0,PARDIR       * Avanzar puntero de lectura
        SUB.W   D0,PARTAM       * Restar caracteres leidos
        BNE     OTRAL           * Si quedan por leer, continuar

* --- Preparar bucle de escritura ---
        MOVE.W  #TAMBS,CONTC    * Total de caracteres a escribir
        MOVE.L  #BUFFER,PARDIR  * Reiniciar puntero al inicio del buffer

* --- Bucle de escritura: escribir en linea B en bloques de TAMBP ---
OTRAE:
        MOVE.W  #TAMBP,PARTAM   * Tamano de bloque de escritura

ESPE:
        MOVE.W  PARTAM,-(A7)    * Parametro: tamano
        MOVE.W  #DESB,-(A7)     * Parametro: descriptor linea B
        MOVE.L  PARDIR,-(A7)    * Parametro: direccion buffer
        BSR     PRINT
        ADD.L   #8,A7           * Limpiar pila
        TST.L   D0
        BEQ     ESPE            * Si no acepto nada, reintentar
        ADD.L   D0,PARDIR       * Avanzar puntero
        SUB.W   D0,CONTC        * Actualizar contador
        BEQ     BUCPR           * Si ya escribimos todo, volver al inicio
        SUB.W   D0,PARTAM       * Actualizar tamano del bloque actual
        BNE     ESPE            * Si no termino el bloque, insistir
        CMP.W   #TAMBP,CONTC    * Quedan menos de TAMBP?
        BHI     OTRAE           * No: siguiente bloque completo
        MOVE.W  CONTC,PARTAM    * Si: ajustar tamano al resto
        BRA     ESPE

* --- Manejadores de excepciones (paran el simulador) ---
BUS_ERR:
        BREAK
        NOP
ADDR_ERR:
        BREAK
        NOP
ILL_INST:
        BREAK
        NOP
PRIV_VIO:
        BREAK
        NOP

*******************************************************************************
* VARIABLES DEL PROGRAMA PRINCIPAL
*******************************************************************************

BUFFER: DS.B    2100            * Buffer para lectura/escritura
PARDIR: DC.L    0               * Direccion parametro
PARTAM: DC.W    0               * Tamano parametro
CONTC:  DC.W    0               * Contador de caracteres a imprimir

*******************************************************************************
* VARIABLE GLOBAL: copia del IMR (el registro IMR no se puede leer)
*******************************************************************************

IMR_COPIA:
        DC.B    IMR_RX          * Inicialmente solo Rx habilitado

        DS.B    1               * Alineamiento (direccion par para siguiente dato)

*******************************************************************************
* SUBRUTINA: INIT
*
* Inicializa la DUART MC68681:
*   - 8 bits por caracter en ambas lineas
*   - Sin eco
*   - RxRDY: interrupcion por cada caracter recibido
*   - 38400 baudios Tx y Rx
*   - Full duplex (Tx y Rx habilitados)
*   - Vector de interrupcion $40
*   - Actualiza tabla de vectores con la direccion de RTI
*   - Inicializa buffers internos llamando a INI_BUFS
*
* Parametros: ninguno
* Resultado:  ninguno
* Modifica:   ninguno (salvo los registros de la DUART)
*******************************************************************************

INIT:
        LINK    A6,#0           * Crear marco de pila (sin variables locales)
        MOVEM.L D0/A0,-(A7)     * Salvar registros que se van a usar

        * --- Configurar ACR: conjunto 1 de velocidades ---
        MOVE.B  #ACR_VAL,ACR

        * --- Configurar linea A ---

        * Reinicializar puntero interno al MR1A
        MOVE.B  #CR_RST,CRA

        * MR1A: 8 bits/caracter, RxRDY
        MOVE.B  #MR1_VAL,MR1A

        * MR2A: modo normal (segundo acceso al mismo puerto va a MR2)
        MOVE.B  #MR2_VAL,MR1A

        * CSRA: 38400 baudios Tx y Rx
        MOVE.B  #CSR_VAL,CSRA

        * CRA: habilitar Tx y Rx
        MOVE.B  #CR_VAL,CRA

        * --- Configurar linea B ---

        * Reinicializar puntero interno al MR1B
        MOVE.B  #CR_RST,CRB

        * MR1B: 8 bits/caracter, RxRDY
        MOVE.B  #MR1_VAL,MR1B

        * MR2B: modo normal
        MOVE.B  #MR2_VAL,MR1B

        * CSRB: 38400 baudios Tx y Rx
        MOVE.B  #CSR_VAL,CSRB

        * CRB: habilitar Tx y Rx
        MOVE.B  #CR_VAL,CRB

        * --- Configurar vector de interrupcion ---
        MOVE.B  #VECT,IVR

        * --- Actualizar tabla de vectores de interrupcion ---
        * Direccion en tabla = VECT * 4 = $40 * 4 = $100
        MOVE.L  #RTI,$100

        * --- Habilitar interrupciones de recepcion en IMR ---
        * Solo Rx A y Rx B; Tx se activara cuando haya datos
        MOVE.B  #IMR_RX,ISRIMR
        MOVE.B  #IMR_RX,IMR_COPIA  * Guardar copia

        * --- Inicializar buffers internos ---
        BSR     INI_BUFS

        MOVEM.L (A7)+,D0/A0     * Restaurar registros
        UNLK    A6
        RTS

*******************************************************************************
* SUBRUTINA: SCAN
*
* Lee hasta Tamano caracteres del buffer interno de recepcion de la linea
* indicada por Descriptor y los copia en Buffer.
* Comportamiento no bloqueante: solo copia lo que haya en el buffer interno.
*
* Parametros en pila (orden de apilado, primero el ultimo):
*   Buffer     (4 bytes, por direccion) - parametro de salida
*   Descriptor (2 bytes, por valor)     - 0=lineaA, 1=lineaB
*   Tamano     (2 bytes, por valor)     - maximo de caracteres a leer
*
* Disposicion del marco de pila (A6):
*   8(A6)  = Buffer    (long)
*   12(A6) = Descriptor (word)
*   14(A6) = Tamano    (word)
*
* Resultado: D0 = numero de caracteres copiados, o $FFFFFFFF si error
*******************************************************************************

SCAN:
        LINK    A6,#0           * Crear marco de pila
        MOVEM.L D1/D2/D3/A0,-(A7)  * Salvar registros

        * --- Validar descriptor ---
        MOVE.W  12(A6),D2       * D2 = Descriptor
        CMP.W   #0,D2
        BEQ     SCAN_OK         * 0 = linea A, valido
        CMP.W   #1,D2
        BEQ     SCAN_OK         * 1 = linea B, valido
        * Descriptor invalido -> error
        MOVE.L  #$FFFFFFFF,D0
        BRA     SCAN_FIN

SCAN_OK:
        * --- Preparar descriptor de buffer interno ---
        * Descriptor 0 -> BUF_RxA (0), Descriptor 1 -> BUF_RxB (1)
        * D2 ya tiene el descriptor correcto (0 o 1)

        MOVE.W  14(A6),D3       * D3 = Tamano (contador de chars restantes)
        MOVE.L  8(A6),A0        * A0 = puntero al buffer de salida
        CLR.L   D1              * D1 = contador de chars leidos

SCAN_LOOP:
        * Comprobar si quedan caracteres por leer
        TST.W   D3
        BEQ     SCAN_DONE       * Si Tamano=0, terminar

        * Deshabilitar interrupciones para acceso atomico al buffer interno
        MOVE.W  SR,-(A7)
        ORI.W   #$0700,SR       * Mascara interrupcion nivel 7

        * Llamar a LEECAR: D0 = descriptor del buffer
        MOVE.L  D2,D0           * D0 = descriptor (BUF_RxA o BUF_RxB)
        BSR     LEECAR

        * Restaurar nivel de interrupciones
        MOVE.W  (A7)+,SR

        * Comprobar resultado
        CMP.L   #$FFFFFFFF,D0
        BEQ     SCAN_DONE       * Buffer vacio, terminar

        * Guardar caracter en buffer de salida
        MOVE.B  D0,(A0)+        * Escribir caracter y avanzar puntero
        ADDQ.L  #1,D1           * Incrementar contador de leidos
        SUBQ.W  #1,D3           * Decrementar contador de pendientes
        BRA     SCAN_LOOP

SCAN_DONE:
        MOVE.L  D1,D0           * D0 = numero de caracteres leidos

SCAN_FIN:
        MOVEM.L (A7)+,D1/D2/D3/A0  * Restaurar registros
        UNLK    A6
        RTS

*******************************************************************************
* SUBRUTINA: PRINT
*
* Copia hasta Tamano caracteres desde Buffer al buffer interno de transmision
* de la linea indicada por Descriptor. Si hay caracteres en el buffer interno,
* activa las interrupciones de transmision para esa linea.
* Comportamiento no bloqueante.
*
* Parametros en pila (orden de apilado, primero el ultimo):
*   Buffer     (4 bytes, por direccion) - parametro de entrada
*   Descriptor (2 bytes, por valor)     - 0=lineaA, 1=lineaB
*   Tamano     (2 bytes, por valor)     - numero de caracteres a escribir
*
* Disposicion del marco de pila (A6):
*   8(A6)  = Buffer    (long)
*   12(A6) = Descriptor (word)
*   14(A6) = Tamano    (word)
*
* Resultado: D0 = numero de caracteres aceptados, o $FFFFFFFF si error
*******************************************************************************

PRINT:
        LINK    A6,#0           * Crear marco de pila
        MOVEM.L D1/D2/D3/A0,-(A7)  * Salvar registros

        * --- Validar descriptor ---
        MOVE.W  12(A6),D2       * D2 = Descriptor
        CMP.W   #0,D2
        BEQ     PRINT_OK
        CMP.W   #1,D2
        BEQ     PRINT_OK
        MOVE.L  #$FFFFFFFF,D0
        BRA     PRINT_FIN

PRINT_OK:
        * El descriptor del buffer de transmision es BUF_TxA (2) o BUF_TxB (3)
        * BUF_TxA = Descriptor + 2
        MOVE.W  D2,D3
        ADDQ.W  #2,D3           * D3 = descriptor buffer Tx (2 o 3)

        MOVE.W  14(A6),D2       * D2 = Tamano (contador de pendientes)
        MOVE.L  8(A6),A0        * A0 = puntero al buffer de entrada
        CLR.L   D1              * D1 = contador de chars aceptados

PRINT_LOOP:
        TST.W   D2
        BEQ     PRINT_DONE      * Si Tamano=0, terminar

        * Deshabilitar interrupciones para acceso atomico al buffer
        MOVE.W  SR,-(A7)
        ORI.W   #$0700,SR

        * Llamar a ESCCAR: D0 = descriptor, D1<7:0> = caracter
        MOVE.L  D3,D0           * D0 = descriptor Tx
        MOVE.B  (A0),D1         * D1 = caracter a insertar
        BSR     ESCCAR

        MOVE.W  (A7)+,SR        * Restaurar interrupciones

        CMP.L   #$FFFFFFFF,D0
        BEQ     PRINT_DONE      * Buffer lleno, no caben mas

        ADDQ.L  #1,A0           * Avanzar puntero fuente
        ADDQ.L  #1,D1           * Incrementar contador de aceptados
        SUBQ.W  #1,D2           * Decrementar pendientes
        BRA     PRINT_LOOP

PRINT_DONE:
        * Si se acepto al menos un caracter, activar interrupciones de Tx
        TST.L   D1
        BEQ     PRINT_NODATOS   * No se copio nada, no activar Tx

        * Recuperar el descriptor original de la linea (0 o 1)
        * D3 tiene el descriptor Tx (2 o 3); el descriptor linea = D3 - 2
        MOVE.W  D3,D0
        SUBQ.W  #2,D0           * D0 = 0 (lineaA) o 1 (lineaB)

        * Activar bit TxRDY correspondiente en IMR
        * Deshabilitar interrupciones para modificacion atomica de IMR
        MOVE.W  SR,-(A7)
        ORI.W   #$0700,SR

        MOVE.B  IMR_COPIA,D2    * Leer copia del IMR
        TST.W   D0
        BNE     PRINT_TxB       * Si descriptor=1, es linea B
        ORI.B   #IMR_TxA,D2     * Activar bit TxRDY linea A
        BRA     PRINT_SETIMR
PRINT_TxB:
        ORI.B   #IMR_TxB,D2     * Activar bit TxRDY linea B
PRINT_SETIMR:
        MOVE.B  D2,ISRIMR       * Escribir nuevo IMR
        MOVE.B  D2,IMR_COPIA    * Actualizar copia

        MOVE.W  (A7)+,SR        * Restaurar interrupciones

PRINT_NODATOS:
        MOVE.L  D1,D0           * D0 = numero de caracteres aceptados

PRINT_FIN:
        MOVEM.L (A7)+,D1/D2/D3/A0
        UNLK    A6
        RTS

*******************************************************************************
* SUBRUTINA: RTI (Rutina de Tratamiento de Interrupcion)
*
* Se invoca cuando la DUART MC68681 solicita una interrupcion (nivel 4).
* Identifica la fuente de interrupcion leyendo el ISR y actua:
*
*   - RxRDY linea A: leer caracter de RBA e insertar en buffer interno Rx A
*   - RxRDY linea B: leer caracter de RBB e insertar en buffer interno Rx B
*   - TxRDY linea A: extraer caracter de buffer interno Tx A y enviarlo por TBA
*                    Si buffer Tx A vacio, deshabilitar interrupcion Tx A en IMR
*   - TxRDY linea B: extraer caracter de buffer interno Tx B y enviarlo por TBB
*                    Si buffer Tx B vacio, deshabilitar interrupcion Tx B en IMR
*
* La RTI termina con RTE (retorno de excepcion).
*******************************************************************************

RTI:
        MOVEM.L D0/D1/D2,-(A7)  * Salvar registros de uso general

        * Leer ISR para identificar fuente de interrupcion
        MOVE.B  ISRIMR,D2       * D2 = contenido del ISR

        * --- Comprobar RxRDY linea A (bit 2) ---
        BTST    #2,D2
        BEQ     RTI_CHK_TxA     * No es recepcion A, continuar

        * Leer caracter del buffer de recepcion de la DUART linea A
        MOVE.B  RBATBA,D1       * D1 = caracter recibido

        * Insertar en buffer interno de recepcion linea A
        MOVE.L  #BUF_RxA,D0
        BSR     ESCCAR

        * Si D0 = $FFFFFFFF el buffer interno esta lleno
        * El caracter ya fue leido del hardware (desactiva la interrupcion)
        * No se puede hacer nada mas con el (se descarta)

RTI_CHK_TxA:
        * --- Comprobar TxRDY linea A (bit 0) ---
        BTST    #0,D2
        BEQ     RTI_CHK_RxB     * No es transmision A, continuar

        * Extraer caracter del buffer interno de transmision linea A
        MOVE.L  #BUF_TxA,D0
        BSR     LEECAR

        CMP.L   #$FFFFFFFF,D0
        BEQ     RTI_TxA_EMPTY   * Buffer vacio: deshabilitar Tx A

        * Enviar caracter por la linea A
        MOVE.B  D0,RBATBA
        BRA     RTI_CHK_RxB

RTI_TxA_EMPTY:
        * Deshabilitar interrupcion TxRDY linea A en IMR
        MOVE.B  IMR_COPIA,D0
        ANDI.B  #$FE,D0
        MOVE.B  D0,ISRIMR
        MOVE.B  D0,IMR_COPIA

RTI_CHK_RxB:
        * --- Comprobar RxRDY linea B (bit 5) ---
        BTST    #5,D2
        BEQ     RTI_CHK_TxB

        * Leer caracter del buffer de recepcion linea B
        MOVE.B  RBBTBB,D1

        * Insertar en buffer interno de recepcion linea B
        MOVE.L  #BUF_RxB,D0
        BSR     ESCCAR

RTI_CHK_TxB:
        * --- Comprobar TxRDY linea B (bit 4) ---
        BTST    #4,D2
        BEQ     RTI_FIN

        * Extraer caracter del buffer interno de transmision linea B
        MOVE.L  #BUF_TxB,D0
        BSR     LEECAR

        CMP.L   #$FFFFFFFF,D0
        BEQ     RTI_TxB_EMPTY

        * Enviar caracter por la linea B
        MOVE.B  D0,RBBTBB
        BRA     RTI_FIN

RTI_TxB_EMPTY:
        * Deshabilitar interrupcion TxRDY linea B en IMR
        MOVE.B  IMR_COPIA,D0
        ANDI.B  #$EF,D0
        MOVE.B  D0,ISRIMR
        MOVE.B  D0,IMR_COPIA

RTI_FIN:
        MOVEM.L (A7)+,D0/D1/D2  * Restaurar registros
        RTE                     * Retorno de excepcion

*******************************************************************************
* INCLUSION DE LA BIBLIOTECA AUXILIAR
* Contiene: INI_BUFS, LEECAR, ESCCAR
*******************************************************************************

        INCLUDE bib_aux.s

