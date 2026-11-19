        ORG     $0
        DC.L    $8000           * Inicializacion del stack pointer
        DC.L    INICIO          * Punto de arranque del programa
 
        ORG     $400 
 
* ============================================================================
* Definicion de constantes y direcciones hardware
* ============================================================================
 
MR1A    EQU     $effc01         * Registro modo canal A (escritura 1)
MR2A    EQU     $effc01         * Registro modo canal A (escritura 2)
SRA     EQU     $effc03         * Estado del canal A (lectura)
CSRA    EQU     $effc03         * Seleccion de baudrate A (escritura)
CRA     EQU     $effc05         * Control del canal A (escritura)
TBA     EQU     $effc07         * Cola de envio A (escritura)
RBA     EQU     $effc07         * Cola de llegada A (lectura)
 
MR1B    EQU     $effc11         * Registro modo canal B (escritura 1)
MR2B    EQU     $effc11         * Registro modo canal B (escritura 2)
SRB     EQU     $effc13         * Estado del canal B (lectura)
CSRB    EQU     $effc13         * Seleccion de baudrate B (escritura)
CRB     EQU     $effc15         * Control del canal B (escritura)
TBB     EQU     $effc17         * Cola de envio B (escritura)
RBB     EQU     $effc17         * Cola de llegada B (lectura)
 
IVR     EQU     $effc19         * Vector de interrupciones
IMR     EQU     $effc0B         * Mascara de interrupciones (escritura)
ISR     EQU     $effc0B         * Estado de las interrupciones (lectura)
ACR     EQU     $effc09         * Registro auxiliar de control
 
CR      EQU     $0D             * Retorno de carro (ASCII)
LF      EQU     $0A             * Salto de linea (ASCII)
FLAGT   EQU     2               * Indicador para enviar
FLAGR   EQU     0               * Indicador para recibir
 
IMRcopia: DC.B  0               * Variable en memoria para respaldar el IMR
          DS.B  1               * Sustituye a EVEN para alinear a direccion par
 
* ============================================================================
* Configuracion inicial de los modulos
* ============================================================================
INIT:   
        * Linea A
        MOVE.B  #%00010000,CRA  * Reset del puntero de modo a MR1A
        MOVE.B  #%00000011,MR1A * Formato: 8 bits por dato
        MOVE.B  #%00000000,MR2A * Deshabilita la opcion de eco
        MOVE.B  #%11001100,CSRA * Ajusta la tasa a 38400 baudios
        MOVE.B  #%00000101,CRA  * Enciende Tx y Rx del puerto A
 
        * Linea B 
        MOVE.B  #%00010000,CRB  * Reset del puntero de modo a MR1B
        MOVE.B  #%00000011,MR1B * Formato: 8 bits por dato
        MOVE.B  #%00000000,MR2B * Deshabilita la opcion de eco
        MOVE.B  #%11001100,CSRB * Ajusta la tasa a 38400 baudios
        MOVE.B  #%00000101,CRB  * Enciende Tx y Rx del puerto B
   
        * Opciones globales 
        MOVE.B  #%00000000,ACR  * Selecciona el bloque de 38400 bps
        MOVE.B  #$40,IVR        * Configura el vector 64 ($40)
        MOVE.B  #%00100010,IMRcopia * Activa interrupciones de Rx para A y B (sec.2.3.10: bit5=RxRDYB, bit1=RxRDYA)
        MOVE.B  IMRcopia,IMR    * Aplica los cambios al hardware
        MOVE.L  #RTI,$100       * Vincula la rutina de atencion al vector $40
 
        BSR     INI_BUFS        * Prepara las estructuras de datos de la libreria
        RTS 
 
* ============================================================================
* SCAN - lee hasta N bytes recibidos de un puerto hacia memoria
*   Pila:  8(A6) = direccion destino
*         12(A6) = puerto (0=A, 1=B)
*         14(A6) = numero de bytes a leer
*   Devuelve en D0 los bytes leidos (-1 si el puerto es invalido)
* ============================================================================
SCAN:
        LINK    A6,#0              * Marco de pila local
        MOVEM.L D1-D5/A0,-(A7)     * Preserva registros de trabajo

        MOVE.L  8(A6),A0           * A0 = destino en memoria
        CLR.L   D5
        MOVE.W  12(A6),D5          * D5 = puerto solicitado
        CLR.L   D4
        MOVE.W  14(A6),D4          * D4 = bytes solicitados

        TST.W   D4                 * Nada que leer -> salir
        BEQ     FIN_SCAN
        CLR.L   D1                 * D1 = contador de bytes leidos

        CMP.W   #1,D5              * Puerto valido? (0=A, 1=B)
        BLS     LEE_LOOP           * BLS (sin signo): 0 y 1 pasan, el resto no

* --- Lectura comun a ambos canales ---
*   El codigo de cola de recepcion de LEECAR coincide con el numero de
*   puerto: 0 = Rx A, 1 = Rx B. Por eso basta copiar D5 a D0.
        MOVEQ   #-1,D0             * Puerto invalido
        BRA     FIN_ERR

LEE_LOOP:
        MOVE.L  D5,D0              * Codigo de cola Rx (0=A, 1=B)
        MOVEM.L D1/D4/D5/A0,-(A7)  * LEECAR altera estos registros
        BSR     LEECAR
        MOVEM.L (A7)+,D1/D4/D5/A0
        CMP.L   #$FFFFFFFF,D0      * Cola vacia?
        BEQ     FIN_SCAN
        MOVE.B  D0,(A0)+           * Guarda el byte y avanza el puntero
        ADDQ.L  #1,D1              * Un byte mas leido
        SUBQ.W  #1,D4              * Un byte menos pendiente
        BNE     LEE_LOOP

FIN_SCAN:
        MOVE.L  D1,D0              * Devuelve el numero de bytes leidos
FIN_ERR:
        MOVEM.L (A7)+,D1-D5/A0     * Restaura el contexto
        UNLK    A6
        RTS

* ============================================================================
* PRINT - encola en transmision N bytes de memoria hacia un puerto
*   Pila:  8(A6) = direccion origen
*         12(A6) = puerto (0=A, 1=B)
*         14(A6) = numero de bytes a enviar
*   Devuelve en D0 los bytes encolados (-1 si el puerto es invalido)
* ============================================================================
PRINT:
        LINK    A6,#0              * Marco de pila local
        MOVEM.L D1-D5/A1,-(A7)     * Preserva registros de trabajo

        MOVE.L  8(A6),A1           * A1 = origen en memoria
        CLR.L   D5
        MOVE.W  12(A6),D5          * D5 = puerto solicitado
        CLR.L   D3
        MOVE.W  14(A6),D3          * D3 = bytes a enviar
        CLR.L   D4                 * D4 = contador de bytes encolados

        TST.W   D3                 * Nada que enviar -> salir
        BEQ     FIN_PRINT

        CMP.W   #1,D5              * Puerto valido? (0=A, 1=B)
        BLS     ESCRIBE_LOOP       * BLS (sin signo): 0 y 1 pasan, el resto no
        MOVEQ   #-1,D0             * Puerto invalido
        BRA     FIN_ERRP

* --- Escritura comun a ambos canales ---
*   El codigo de cola de transmision de ESCCAR es puerto+2: 2 = Tx A, 3 = Tx B.
ESCRIBE_LOOP:
        MOVE.L  D5,D0
        ADDQ.L  #2,D0              * Codigo de cola Tx (2=A, 3=B)
        CLR.L   D1
        MOVE.B  (A1)+,D1           * Carga el byte a enviar
        MOVEM.L D3-D5/A1,-(A7)     * ESCCAR altera estos registros
        BSR     ESCCAR
        MOVEM.L (A7)+,D3-D5/A1
        CMP.L   #$FFFFFFFF,D0      * Cola llena?
        BEQ     FIN_TX
        ADDQ.L  #1,D4              * Un byte mas encolado
        SUBQ.W  #1,D3              * Un byte menos pendiente
        BNE     ESCRIBE_LOOP
FIN_TX:
        TST.L   D4                 * Se encolo algo?
        BEQ     FIN_PRINT
*   El bit de Tx dentro de IMR es puerto*4: bit 0 = Tx A, bit 4 = Tx B.
*   LSL.L #2 multiplica el numero de puerto por cuatro para obtener ese bit.
        MOVE.L  D5,D2
        LSL.L   #2,D2              * Bit IMR = puerto*4 (0=Tx A, 4=Tx B)
        CLR.L   D1
        MOVE.B  IMRcopia,D1
        BSET    D2,D1              * Activa la interrupcion Tx del puerto
        MOVE.B  D1,IMRcopia
        MOVE.B  IMRcopia,IMR
        BRA     FIN_PRINT

FIN_PRINT:
        MOVE.L  D4,D0              * Devuelve el numero de bytes encolados
FIN_ERRP:
        MOVEM.L (A7)+,D1-D5/A1      * Restaura el contexto
        UNLK    A6
        RTS

* ============================================================================
* RTI - manejador de interrupciones de la DUART
*   Atiende en bucle todas las fuentes activas y autorizadas por IMRcopia
* ============================================================================
RTI:
* ----------------------------------------------------------------------------
* SOLUCION A UN BUG DEL EMULADOR BSVC (sim68000)
*
* En un MC68000 real, al aceptar una interrupcion de nivel N el hardware fija
* la mascara de la SR a N, de modo que toda peticion de nivel <= N queda
* inhibida hasta el RTE. Por tanto NO existe anidamiento al mismo nivel: la
* propia RTI no puede reentrar mientras se ejecuta.
*   Manual de referencia: "M68000 8-/16-/32-Bit Microprocessors User's Manual"
*   (Motorola, Rev 8, 1993), seccion 6.3.2 "Interrupts", pag. 6-12:
*   "interrupts are inhibited for all priority levels less than or equal to the
*    current priority" ... "the processor priority level is set to the level of
*    the interrupt being acknowledged".
*
* BSVC compara mal: en src/M68k/sim68000/m68000.cpp, funcion ServiceInterrupts():
*   if (interrupt.level < interrupt_mask && interrupt.level != 7) ...
* Usa "<" en lugar de "<=", asi que una peticion de nivel 3 se entrega mientras
* ya se atiende el nivel 3, reentrando la RTI a mitad de LEECAR/ESCCAR y
* duplicando un caracter. Subir la mascara a 7 emula lo que hace el hardware
* implicitamente; el RTE restaura la SR original al salir.
* ----------------------------------------------------------------------------
        ORI.W   #$0700,SR          * Bloquea el anidamiento de la propia RTI
        MOVEM.L D0-D7/A0-A6,-(A7)  * Preserva todo el contexto

BUCLE:
        CLR.L   D1
        CLR.L   D2
        MOVE.B  ISR,D1             * Banderas de interrupcion activas
        MOVE.B  IMRcopia,D2        * Interrupciones autorizadas
        AND.B   D1,D2              * Solo las activas y autorizadas
        BTST    #0,D2              * Tx A libre?
        BNE     TRAN_A
        BTST    #1,D2              * Rx A con dato?
        BNE     RECP_A
        BTST    #4,D2              * Tx B libre?
        BNE     TRAN_B
        BTST    #5,D2              * Rx B con dato?
        BNE     RECP_B
        BRA     FIN_RTI            * Nada pendiente -> salir

* --- Canal A ---
TRAN_A:
        MOVEQ   #2,D0              * Origen: cola de transmision A
        BSR     LEECAR
        CMP.L   #-1,D0             * Sin datos que enviar?
        BEQ     NO_INT_A
        MOVE.B  D0,TBA             * Envia el byte por el canal A
        BRA     BUCLE
NO_INT_A:
        CLR.L   D4
        MOVE.B  IMRcopia,D4
        BCLR    #0,D4              * Desactiva la interrupcion Tx A
        MOVE.B  D4,IMRcopia
        MOVE.B  IMRcopia,IMR
        BRA     FIN_RTI
RECP_A:
        CLR.L   D1
        MOVE.B  RBA,D1             * Lee el byte recibido en A
        MOVEQ   #0,D0              * Destino: cola de recepcion A
        BSR     ESCCAR
        BRA     BUCLE

* --- Canal B ---
TRAN_B:
        MOVEQ   #3,D0              * Origen: cola de transmision B
        BSR     LEECAR
        CMP.L   #-1,D0             * Sin datos que enviar?
        BEQ     NO_INT_B
        MOVE.B  D0,TBB             * Envia el byte por el canal B
        BRA     BUCLE
NO_INT_B:
        CLR.L   D4
        MOVE.B  IMRcopia,D4
        BCLR    #4,D4              * Desactiva la interrupcion Tx B
        MOVE.B  D4,IMRcopia
        MOVE.B  IMRcopia,IMR
        BRA     FIN_RTI
RECP_B:
        CLR.L   D1
        MOVE.B  RBB,D1             * Lee el byte recibido en B
        MOVEQ   #1,D0              * Destino: cola de recepcion B
        BSR     ESCCAR
        BRA     BUCLE

FIN_RTI:
        MOVEM.L (A7)+,D0-D7/A0-A6  * Restaura el contexto
        RTE                        * Fin de la excepcion
 
* ============================================================================
* ============================================================================
* PROGRAMA PRINCIPAL DE PRUEBA
* ============================================================================
 
BUFFER: DS.B    2100            * Espacio reservado para operaciones
PARDIR: DC.L    0               * Puntero a la ubicacion actual
PARTAM: DC.W    0               * Bytes a procesar
CONTC:  DC.W    0               * Control de lo que falta por hacer
DESA:   EQU     0               * Constante canal A
DESB:   EQU     1               * Constante canal B
TAMBS:  EQU     5               * Bloques de recepcion
TAMBP:  EQU     5               * Bloques de envio
 
INICIO: 
        MOVE.L  #BUS_ERROR,8    * Captura errores de bus
        MOVE.L  #ADDRESS_ER,12  * Captura direcciones impares
        MOVE.L  #ILLEGAL_IN,16  * Captura instrucciones invalidas
        MOVE.L  #PRIV_VIOLT,32  * Captura faltas de privilegios
        MOVE.L  #ILLEGAL_IN,40  * Captura coprocesador
        MOVE.L  #ILLEGAL_IN,44  * Captura coprocesador
 
        BSR     INIT            * Prepara hardware
        MOVE.W  #$2000,SR       * Baja el nivel de interrupcion
 
BUCPR:  
        MOVE.W  #TAMBS,PARTAM   * Asigna bloques de trabajo
        MOVE.L  #BUFFER,PARDIR  * Fija el inicio de memoria
OTRAL:  
        MOVE.W  PARTAM,-(A7)    * Push tamano
        MOVE.W  #DESA,-(A7)     * Push ID
        MOVE.L  PARDIR,-(A7)    * Push puntero
 
ESPL:   
        BSR     SCAN            * Invoca lectura
        ADD.L   #8,A7           * Limpia pila local
        ADD.L   D0,PARDIR       * Ajusta puntero con exito
        SUB.W   D0,PARTAM       * Descuenta bytes conseguidos
        BNE     OTRAL           * Insiste si faltan datos
        
        MOVE.W  #TAMBS,CONTC    * Resetea bloques para imprimir
        MOVE.L  #BUFFER,PARDIR  * Vuelve al principio del texto
OTRAE:  
        MOVE.W  #TAMBP,PARTAM   * Ajusta limite de envio
ESPE:   
        MOVE.W  PARTAM,-(A7)    * Push tamano
        MOVE.W  #DESA,-(A7)     * Push ID
        MOVE.L  PARDIR,-(A7)    * Push puntero
        BSR     PRINT           * Invoca envio
        ADD.L   #8,A7           * Limpia pila local
        
        ADD.L   D0,PARDIR       * Ajusta puntero con exito
        SUB.W   D0,CONTC        * Descuenta lo mandado del total
        BEQ     SALIR           * Todo completado, reiniciar
        SUB.W   D0,PARTAM       * Descuenta lo mandado del bloque
        BNE     ESPE            * Insiste si el bloque no acabo
        
        CMP.W   #TAMBP,CONTC    * Faltan menos bytes que un bloque?
        BHI     OTRAE           * Si falta mas, ciclo normal
        MOVE.W  CONTC,PARTAM    * Si no, ajusta el ultimo bloque
        BRA     ESPE            * Envia resto
 
SALIR:  
        BRA     BUCPR           * Bucle principal infinito
 
BUS_ERROR:  
        BREAK                   * Detencion por bus
        NOP 
ADDRESS_ER: 
        BREAK                   * Detencion por alineacion
        NOP  
ILLEGAL_IN: 
        BREAK                   * Detencion por instruccion
        NOP 
PRIV_VIOLT: 
        BREAK                   * Detencion por permisos
        NOP 
 
        INCLUDE bib_aux.s       * Archivo auxiliar proporcionado
