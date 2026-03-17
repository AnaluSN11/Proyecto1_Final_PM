/*
 * Proyecto1_Fase5_PM1.asm
 * Creado: 13/03/2026 11:11:07
 * Autor : AnaLucia
 * Descripcion: Reloj funcionando correctamente. Se muestra la hora, la fecha, permite configurar estos valores y la alarma está integrada. 
 */

 /****************************************/
// Encabezado
.include "M328PDEF.inc"

.dseg
STATE:				.byte 1		// Estado actual del sistema
COUNTER_OVF_CLK:	.byte 1		// Contador de overflows para 500ms
FLAG_DP:			.byte 1		// Bandera para el punto 
FLAG_CLK:			.byte 1		// Bandera para el minuto
FLAG_FIX_TIME:		.byte 1		// Bandera overflow/underflow reloj
FLAG_FIX_DATE:		.byte 1		// Bandera overflow/underflow fecha
FLAG_FIX_ALARM:		.byte 1		// Bandera overflow/underflow alarma
FLAG_ALARM_FIRED:	.byte 1		// Bandera para que solo suene 1 vez la alarma
MUX_INDEX:			.byte 1		// Display activo (0-3)
// Variables de edición
EDIT_D1:			.byte 1
EDIT_D2:			.byte 1
EDIT_D3:			.byte 1
EDIT_D4:			.byte 1
// Variables de la alarma
ALARM_MINU:			.byte 1
ALARM_MIND:			.byte 1		
ALARM_HORU:			.byte 1		
ALARM_HORD:			.byte 1
// Registros para el reloj (minutos y horas)
COUNTER_MINU:		.byte 1
COUNTER_MIND:		.byte 1
COUNTER_HORU:		.byte 1
COUNTER_HORD:		.byte 1
// Registros para la fecha (dia y mes)
COUNTER_DIAU:		.byte 1
COUNTER_DIAD:		.byte 1
COUNTER_MESU:		.byte 1
COUNTER_MESD:		.byte 1

.org SRAM_START

.cseg
// Estados
.equ	SHOW_TIME	= 0
.equ	SHOW_DATE	= 1
.equ	SET_TIME	= 2
.equ	SET_DATE	= 3	
.equ	SET_ALARM	= 4
.equ	ALARM_RING	= 5
// Variables para cargar a los Timers
.equ	T1VALUE		= 0x1B1E
.equ	T0VALUE		= 0x0C

/****************************************/
// Vectores de interrupcion
.org 0x00
	JMP START
.org PCI1addr
	JMP	PCINT_ISR
.org OC2Aaddr
	JMP	TIMR2_ISR
.org OVF1addr
	JMP	TIMR1_ISR
.org OVF0addr
	JMP	TIMR0_ISR

/****************************************/
// Configuracion de pila
START: 
	CLR		R1
	LDI		R16, LOW(RAMEND)
	OUT		SPL, R16
	LDI		R16, HIGH(RAMEND)
	OUT		SPH, R16

/****************************************/
// Configuracion MCU
SETUP:
	CLI
	;----- PRESCALER (1MHz) -----;
	LDI		R16, (1<<CLKPCE)
	STS		CLKPR, R16
	LDI		R16, (1<<CLKPS2)
	STS		CLKPR, R16
	;----- BOTONES (PC0-PC4) Y BUZZER (PC5) -----;
	LDI		R16, 0x20					// PC5 salida, PC0-PC4 entradas
	OUT		DDRC, R16
	LDI		R16, 0x1F					// Pull-ups activados en PC0-PC4
	OUT		PORTC, R16
	;----- DISPLAY (PORTD) -----;
	LDI		R16, 0xFF
	OUT		DDRD, R16
	LDI		R16, 0x00					// Disable UART
	STS		UCSR0B, R16
	;----- TRANSISTORES (PB0-PB3) Y LEDs (PB4-PB5) -----;
	LDI		R16, 0xFF
	OUT		DDRB, R16
	;----- TIMERS -----;
	CALL	INIT_TMR2
	CALL	INIT_TMR1
	CALL	INIT_TMR0
	;----- PIN CHANGE (PC0-PC4) -----;
	LDI		R16, (1<<PCIE1)
	STS		PCICR, R16
	LDI		R16, 0x1F
	STS		PCMSK1, R16
	;----- INICIALIZACIÓN DE VARIABLES -----;
	CALL	INIT_VAR
	;----- ACTIVAR INTERRUPCIONES GLOBALES -----;
	SEI

/****************************************/
// Loop Infinito
MAIN_LOOP:
	;----- REVISAR RELOJ -----;
	LDS		R16, FLAG_CLK				// Cuando la bandera esta activa es porque ha pasado 1min así que actualizamos valores
	CPI		R16, 1
	BRNE	CHECK_ALARM_LOOP			// Si no ha pasado un minuto mientras tanto verficamos la alarma
	RCALL	REVISAR_CLK					// Si pasó un minuto revisamos el reloj
CHECK_ALARM_LOOP:
	RCALL	CHECK_ALARM_NOW				// Revisamos la alarma
CHECK_FIX_TIME:
	LDS		R16, FLAG_FIX_TIME			// Arreglamos overflow y underflow cuando se hace cónfiguración del reloj
	CPI		R16, 1
	BRNE	CHECK_FIX_DATE
	RCALL	FIX_TIME
	LDI		R17, 0
	STS		FLAG_FIX_TIME, R17			// Limpiamos al finalizar la bandera para poder hacer el arreglo constante
CHECK_FIX_DATE:
	LDS		R16, FLAG_FIX_DATE			// Arreglamos overflow y underflow cuando se hace cónfiguración de la fecha
	CPI		R16, 1
	BRNE	CHECK_FIX_ALARM
	RCALL	FIX_DATE
	LDI		R17, 0
	STS		FLAG_FIX_DATE, R17			// Limpiamos al finalizar la bandera para poder hacer el arreglo constante
CHECK_FIX_ALARM:
	LDS		R16, FLAG_FIX_ALARM			// Arreglamos overflow y underflow cuando se hace cónfiguración de la alarma
	CPI		R16, 1
	BRNE	MAIN_LOOP_END
	RCALL	FIX_ALARM
	LDI		R17, 0
	STS		FLAG_FIX_ALARM, R17			// Limpiamos al finalizar la bandera para poder hacer el arreglo constante
MAIN_LOOP_END:
	RJMP	MAIN_LOOP

/****************************************/
// Subrutinas no-interrupcion
INIT_TMR2:								// Configuración del Timer2
	LDI		R16, (1<<WGM21)				// Modo CTC
	STS		TCCR2A, R16
	LDI		R16, (1<<CS22)				// Prescaler de 64
	STS		TCCR2B, R16
	LDI		R16, 16
	STS		OCR2A, R16					// Cargamos 16 para que sea aproximadamente 1ms
	LDI		R16, (1<<OCIE2A)
	STS		TIMSK2, R16					// Activamos interrupción para Compare Match A
	RET
INIT_TMR1:								// Configuración del Timer1
	LDI		R16, 0x00					// Modo normal
	STS		TCCR1A, R16
	LDI		R16, (1<<CS12) | (1<<CS10)	// Prescaler 1024
	STS		TCCR1B, R16
	LDI		R16, HIGH(T1VALUE)			// Cargamos el valor calculado para que pasen 60 segundos
	STS		TCNT1H, R16
	LDI		R16, LOW(T1VALUE)
	STS		TCNT1L, R16
	LDI		R16, (1<<TOIE1)				// Activamos interrupción de tipo overflow
	STS		TIMSK1, R16
	RET	
INIT_TMR0:								// Configuración del Timer0
	LDI		R16, 0x00					// Modo normal
	OUT		TCCR0A, R16
	LDI		R16, (1<<CS02) | (1<<CS00)	// Prescaler 1024
	OUT		TCCR0B, R16
	LDI		R16, T0VALUE				// Cargamos el valor para que sea aprox 250ms
	OUT		TCNT0, R16
	LDI		R16, (1<<TOIE0)				// Activamos interrupción tipo overflow
	STS		TIMSK0, R16
	RET
INIT_VAR:								// Inicialización de todas las variables
	CLR		R16
	STS		COUNTER_OVF_CLK, R16
	STS		FLAG_DP, R16
	STS		FLAG_FIX_TIME, R16
	STS		FLAG_FIX_DATE, R16
	STS		FLAG_FIX_ALARM, R16
	STS		FLAG_ALARM_FIRED, R16
	STS		STATE, R16
	STS		MUX_INDEX, R16
	STS		EDIT_D1, R16
	STS		EDIT_D2, R16
	STS		EDIT_D3, R16
	STS		EDIT_D4, R16
	STS		COUNTER_MINU, R16
	STS		COUNTER_MIND, R16
	STS		COUNTER_HORU, R16
	STS		COUNTER_HORD, R16
	STS		COUNTER_DIAD, R16
	STS		COUNTER_MESD, R16
	STS		ALARM_MINU, R16				// Inicializamos la alarma en un valor que no vaya a suceder, 25:00. Así suena solo después de haber configurado un valor
	STS		ALARM_MIND, R16
	LDI		R16, 5
	STS		ALARM_HORU, R16
	LDI		R16, 2
	STS		ALARM_HORD, R16
	LDI		R16, 1
	STS		COUNTER_DIAU, R16			// Para que inicie en fecha 01/01 cargamos uno a los displays de DIA unidades y MES unidades	
	STS		COUNTER_MESU, R16
	CBI		PORTD, 0
	CBI		PORTC, 5
	RET

/****************************************/
CHECK_ALARM_NOW:
	LDS		R16, FLAG_ALARM_FIRED		// Si la alarma ya fue disparada, no volver a activar
	CPI		R16, 1
	BREQ	EXIT_CHECK_ALARM
	;----- VERIFICAR ALARMA -----;
	LDS		R16, ALARM_MINU
	LDS		R17, COUNTER_MINU
	CP		R16, R17					// Comparamos los MINU del valor configurado de la alarma con el contador del reloj
	BRNE	EXIT_CHECK_ALARM			// Si no coinciden, salimos

	LDS		R16, ALARM_MIND				
	LDS		R17, COUNTER_MIND
	CP		R16, R17					// Si coinciden, comparamos los MIND del valor configurado de la alarma con el contador del reloj
	BRNE	EXIT_CHECK_ALARM			// Si no coinciden, salimos

	LDS		R16, ALARM_HORU
	LDS		R17, COUNTER_HORU
	CP		R16, R17					// Si coinciden, comparamos las HORU del valor configurado de la alarma con el contador del reloj
	BRNE	EXIT_CHECK_ALARM			// Si no coinciden, salimos

	LDS		R16, ALARM_HORD
	LDS		R17, COUNTER_HORD
	CP		R16, R17					// Si coincinden, comparamos las HORD del valor configurado de la alarma con el contador del reloj
	BRNE	EXIT_CHECK_ALARM			// Si no coinciden, salimos
	
	LDI		R16, ALARM_RING				// Para este punto todo ha de haber coincidido, así que activamos la alarma (buzzer)
	STS		STATE, R16
	SBI		PORTC, 5
	LDI		R16, 1
	STS		FLAG_ALARM_FIRED, R16		// Marcamos que ya fue disparada
EXIT_CHECK_ALARM:						// Salimos de la verificación de la alarma
	RET	


REVISAR_CLK:							// Subrutina para verificar el incremento del reloj cuando esta en SHOW_TIME
	;----- MINUTOS -----;
	LDS		R16, COUNTER_MINU			// Incrementamos los MINU
	INC		R16
	STS		COUNTER_MINU, R16
	CPI		R16, 10						// Verificamos si llegó a 10
	BRSH	CONTINUE					// Si es 10 o mayor reiniciamos
	RJMP	EXIT_REVISAR_CLK			// Si no entonces salimos
CONTINUE:
	CLR		R16	
	STS		COUNTER_MINU, R16			// Reiniciamos el contador de MINU
	LDS		R16, COUNTER_MIND
	INC		R16
	STS		COUNTER_MIND, R16			// Incrementamos el contador de MIND
	CPI		R16, 6						// Verificamos si llegó a 6
	BRLO	EXIT_REVISAR_CLK			// Si no entonces salimos

	CLR		R16
	STS		COUNTER_MIND, R16			// Si llegó a 6 entonces limpiamos tanto MIND como MINU
	STS		COUNTER_MINU, R16
	;----- HORAS (formato 24 horas) -----;
	LDS		R16, COUNTER_HORU
	INC		R16
	STS		COUNTER_HORU, R16			// Incrementamos el contador de HORU
	LDS		R17, COUNTER_HORD
	CPI		R17, 2						// Verificamos el caso en el que nos encontramos
	BRNE	CHECK_NORMAL_HOUR
	// HORD = 2 (HORU entonces solo puedo llegar a 3)
	CPI		R16, 4						// Verificamos si llegó a 24
	BRLO	EXIT_REVISAR_CLK			// Si no, salimos

	CLR		R16
	STS		COUNTER_HORU, R16			// Si llegó a 24 reiniciamos HORU y HORD
	STS		COUNTER_HORD, R16
	RCALL	INC_DATE					// Como pasó un día incrementamos la fecha
	RJMP	EXIT_REVISAR_CLK
CHECK_NORMAL_HOUR:						// Si aún no ha pasado las 20 horas incrementamos la hora de manera normal 
	CPI		R16, 10
	BRLO	EXIT_REVISAR_CLK			// Verificamos si HORU llegó a 10

	CLR		R16
	STS		COUNTER_HORU, R16			// Si llegó a 10 entonces reiniciamos HORU
	LDS		R17, COUNTER_HORD
	INC		R17
	STS		COUNTER_HORD, R17			// Incrementamos HORD

	CPI		R17, 3						// Verificamos si HORD llegó a 3
	BRLO	EXIT_REVISAR_CLK			// Si no ha llegado, salimos

	CLR		R16
	STS		COUNTER_HORU, R16			//Si llegó a 3, limpiamos HORU y HORD
	STS		COUNTER_HORD, R16
EXIT_REVISAR_CLK:
	LDI		R16, 0
	STS		FLAG_CLK, R16				// Limpiamos la bandera para revisar continuamente cada vez que pasa 1 min
	STS		FLAG_ALARM_FIRED, R16		// Limpiamos la bandera de la alarma para que pueda sonar otra vez 
	RET

INC_DATE:								// Incremento de la fecha (sucede cada 24 horas)
	;----- UNIDADES DE DIA -----;
	LDS		R16, COUNTER_DIAU
	INC		R16
	STS		COUNTER_DIAU, R16			// Incrementamos el DIAU
	CPI		R16, 10						// Verificamos si llegó a 10
	BRLO	CHECK_MONTH					// Si no, verficamos el mes

	CLR		R16
	STS		COUNTER_DIAU, R16			// Si llegó a 10 limpiamos DIAU
	LDS		R16, COUNTER_DIAD
	INC		R16
	STS		COUNTER_DIAD, R16			// Incrementamos DIAD
CHECK_MONTH:							// Revisión del mes
	;----- DIAS POR DEFECTO = 31 -----;
	LDI		R16, 31
	;----- FEBRERO -----;
	LDS		R17, COUNTER_MESD			// Revisamos si es el caso especial de febrero
	CPI		R17, 0
	BRNE	NOT_FEB						

	LDS		R17, COUNTER_MESU
	CPI		R17, 2
	BRNE	NOT_FEB

	LDI		R16, 28						// Si estamos en febrero cargamos a R16 28 días y verificamos el día 
	RJMP	CHECK_DAY
NOT_FEB:								// Si no es febrero seguimos
	;----- MESES DE 30 DIAS -----;
	LDS		R17, COUNTER_MESU
	CPI		R17, 4						// Verificamos Abril
	BREQ	SET30
	CPI		R17, 6						// Verificamos Junio
	BREQ	SET30
	CPI		R17, 9						// Verificamos Septiembre
	BREQ	SET30
	LDS		R17, COUNTER_MESD			// Verificamos Noviembre
	CPI		R17, 1
	BRNE	CHECK_DAY
	LDS		R17, COUNTER_MESU
	CPI		R17, 1
	BREQ	SET30
	RJMP	CHECK_DAY					// Si no es de 30 días seguimos
SET30:
	LDI		R16, 30						// Si es de 30 días cargamos a R16 30
CHECK_DAY: 
	;----- CONVERTIR DIA BCD A BINARIO -----;
	LDS		R17, COUNTER_DIAD
	LDI		R18, 10
	MUL		R17, R18					// Multiplicamos el valor de las decenas por 10
	MOV		R17, R0						// El resultado de la multiplicación se almacena en R0, lo movemos a R17
	LDS		R18, COUNTER_DIAU			
	ADD		R17, R18					// Sumamos las decenas con las unidades para obtener en un solo registro el valor del día
	CLR		R1							// Al efectuar la multiplicación siempre se debe limpiar R1
	;----- COMPARAR DIA VS MAX -----;
	CP		R17, R16					// Comparamos si el día llegó al máximo (R16)
	BRSH	DAY_OVERFLOW_CLK			// Si llegó al máximo entonces realizamos overflow
	RJMP	EXIT_INC_DATE				// Si no salimos del incremento de la fecha
DAY_OVERFLOW_CLK:
	;----- REINICIAR DIA -----;
	LDI		R16, 1
	STS		COUNTER_DIAU, R16			// Reiniciamos día a 01
	CLR		R16
	STS		COUNTER_DIAD, R16
	;----- INCREMENTAR MES -----;
	LDS		R16, COUNTER_MESU			// Incrementamos el mes
	INC		R16
	STS		COUNTER_MESU, R16

	CPI		R16, 10						// Verificamos si MESU llegó a 10
	BRLO	CHECK_MONTH_LIMIT			// Si no ha llegado a 10 verificamos el mes límite

	CLR		R16							// Si llegó a 10 reiniciamos MESU
	STS		COUNTER_MESU, R16
	LDS		R16, COUNTER_MESD
	INC		R16
	STS		COUNTER_MESD, R16			// Incremetamos MESD
CHECK_MONTH_LIMIT:
	// CONVERTIR MES A BINARIO (proceso descrito anteriormente)
	LDS		R16, COUNTER_MESD
	LDI		R17, 10
	MUL		R16, R17
	MOV		R16, R0
	CLR		R1
	LDS		R17, COUNTER_MESU
	ADD		R16, R17
	
	CPI		R16, 13						// Verificar si pasó de 12
	BRLO	EXIT_INC_DATE				// Si no ha pasado de 12 salimos
	;----- VOLVER A ENERO -----;
	CLR		R16							// Si pasó de 12 volvemos a enero 01
	STS		COUNTER_MESD, R16
	LDI		R16, 1
	STS		COUNTER_MESU, R16
EXIT_INC_DATE:
	RET


FIX_TIME:
	PUSH	R16							// Protegemos los registros que utilizaremos en la subrutina
	PUSH	R17
	PUSH	R18
	;----- MINUTOS -----;
	// BCD -> BINARIO (proceso descrito anteriormente)
	LDS		R17, EDIT_D2
	LDI		R18, 10
	MUL		R17, R18
	MOV		R17, R0
	CLR		R1
	LDS		R18, EDIT_D1
	ADD		R17, R18
	;----- UNDERFLOW (-1) -----;
	CPI		R17, 200					// En este caso comparamos con 200 porque al hacer underflow genera un valor grande
	BRLO	CHECK_MIN_OVER				// Si el valor es menor que 200, no hubo underflow se revisa overflow
	LDI		R17, 59						// Si hubo underflow, se corrige a 59 min
	RJMP	SAVE_MIN					// Guardamos los minutos
	;----- OVERFLOW (60) -----;
CHECK_MIN_OVER: 
	CPI		R17, 60						// Comparamos los minutos con 60
	BRLO	SAVE_MIN					// Si es menor, no es overflow, guardamos minutos
	CLR		R17							// Si no, reiniciamos los minutos 00
SAVE_MIN: 
	;----- BINARIO -> BCD -----;
	CLR		R16							// Utilizamos R16 para contar cuántas veces restamos 10 (serían las decenas)
	LDI		R18, 10						// Cargamos 10 para usarlo como divisor para las decenas
DIV_MIN:
	CPI		R17, 10						// Verificamos si el valor es menor que 10
	BRLO	DIV_MIN_END					// Si el valor es menor que 10 ya solo guardamos
	SUB		R17, R18					// Si es mayor restamos 10 a los minutos
	INC		R16							// Incrementamos las decenas
	RJMP	DIV_MIN						// Así hasta hacer la división a decenas (R16) y unidades (R17)
DIV_MIN_END:
	STS		EDIT_D2, R16
	STS		EDIT_D1, R17
	// Para las horas utilizamos exactamente la misma lógica que para los minutos
	;----- HORAS -----;
	// BCD -> BINARIO 
	LDS		R17, EDIT_D4
	LDI		R18, 10
	MUL		R17, R18
	MOV		R17, R0
	CLR		R1
	LDS		R18, EDIT_D3
	ADD		R17, R18
	;----- UNDERFLOW -----;
	CPI		R17, 200
	BRLO	CHECK_HOUR_OVER
	LDI		R17, 23
	RJMP	SAVE_HOUR
	;----- OVERFLOW -----;
CHECK_HOUR_OVER:
	CPI		R17, 24
	BRLO	SAVE_HOUR
	CLR		R17
SAVE_HOUR:
	;----- BINARIO -> BCD -----;
	CLR		R16
	LDI		R18, 10
DIV_HOUR:
	CPI		R17, 10
	BRLO	DIV_HOUR_END
	SUB		R17, R18
	INC		R16
	RJMP	DIV_HOUR
DIV_HOUR_END:
	STS		EDIT_D4, R16
	STS		EDIT_D3, R17

	POP		R18
	POP		R17
	POP		R16
	RET

FIX_DATE: 
	PUSH	R16
	PUSH	R17
	PUSH	R18
	;----- CALCULAR MES BCD -> BINARIO -----;
	LDS		R16, EDIT_D2
	LDI		R17, 10
	MUL		R16, R17
	MOV		R18, R0
	CLR		R1
	LDS		R16, EDIT_D1
	ADD		R18, R16
	;----- CORREGIR MES -----;
	CPI		R18, 13						// Verificamos si el mes llegó a 13
	BRLO	CHECK_MONTH_UNDER			// Si no ha llegado verificamos underflow
	
	LDI		R18, 1						
	RJMP	SAVE_MONTH					// Reiniciamos meses a enero 01
CHECK_MONTH_UNDER:
	CPI		R18, 0						// Si el mes llegó a 0 entonces hubo underflow
	BRNE	SAVE_MONTH					// Si no hay underflow guardamos el mes

	LDI		R18, 12						// Si hay underflow pasamos al diciembre 12
SAVE_MONTH:
	;----- CONVERTIR MES BINARIO A BCD -----;
	LDI		R17, 10
	CLR		R16
MONTH_DIV:
	CPI		R18, 10
	BRLO	MONTH_END
	SUB		R18, R17
	INC		R16
	RJMP	MONTH_DIV
MONTH_END:
	STS		EDIT_D2, R16
	STS		EDIT_D1, R18
	;----- DETERMINAR MAX DIA -----;
	// Misma lógica que cuando incrementamos la fecha
	// MES BINARIO
	LDS		R16, EDIT_D2
	LDI		R17, 10
	MUL		R16, R17
	MOV		R18, R0
	CLR		R1
	LDS		R16, EDIT_D1
	ADD		R18, R16
	// CANTIDAD DE DIAS POR DEFAULT
	LDI		R17, 31
	// MES DE FEBRERO
	CPI		R18, 2
	BRNE	CHECK_30
	
	LDI		R17, 28
	RJMP	CHECK_FIX_DAY
CHECK_30:
	CPI		R18, 4
	BREQ	FIX_SET30
	CPI		R18, 6
	BREQ	FIX_SET30
	CPI		R18, 9
	BREQ	FIX_SET30
	CPI		R18, 11
	BREQ	FIX_SET30
	RJMP	CHECK_FIX_DAY
FIX_SET30:
	LDI		R17, 30
	;----- CALCULAR DIA BINARIO -----;
CHECK_FIX_DAY:
	LDS		R16, EDIT_D4
	LDI		R18, 10
	MUL		R16, R18
	MOV		R16, R0
	CLR		R1
	LDS		R18, EDIT_D3
	ADD		R16, R18
	;----- CORREGIR DIA -----;
	CP		R16, R17
	BRLO	CHECK_DAY_UNDER
	BREQ	CHECK_DAY_UNDER
	// OVERFLOW -> 01
	LDI		R16, 1
	RJMP	SAVE_DAY
CHECK_DAY_UNDER:
	CPI		R16, 0
	BRNE	SAVE_DAY
	// UNDERFLOW -> MAX_DIA
	MOV		R16, R17
SAVE_DAY:
	;----- CONVERTIR DIA A BCD -----;
	LDI		R18, 10
	CLR		R17
DAY_DIV:
	CPI		R16, 10
	BRLO	DAY_END
	SUB		R16, R18
	INC		R17
	RJMP	DAY_DIV
DAY_END:
	STS		EDIT_D4, R17
	STS		EDIT_D3, R16

	POP		R18
	POP		R17
	POP		R16
	RET


FIX_ALARM:								// Como usamos variables editables, podemos reciclar la rutina de FIX_TIME para FIX_ALARM
	RCALL	FIX_TIME
	RET

/****************************************/
// ISR Timer2 - Multiplexado de displays (~1ms)
TIMR2_ISR:
	PUSH	R16							// Guardar registros en la pila para no corromperlos
	PUSH	R17
	PUSH	R18
	PUSH	ZH
	PUSH	ZL
	IN		R16, SREG					// Guardar el SREG en la pila
	PUSH	R16
	;----- APAGAR TODOS LOS DISPLAYS -----;
	CBI		PORTB, 0
	CBI		PORTB, 1
	CBI		PORTB, 2
	CBI		PORTB, 3
	;----- LEER ÍNDICE DE DISPLAY -----;
	LDS		R17, MUX_INDEX				// Cargar qué display toca encender 
	;----- SELECCIONAR MODO DE VISUALIZACIÓN -----;
	LDS		R16, STATE					// Cargamos el estado actual
	CPI		R16, SET_TIME				// Verificar modo editar hora
	BREQ	SHOW_EDIT
	CPI		R16, SET_DATE				// Verificar modo editar fecha
	BREQ	SHOW_EDIT
	CPI		R16, SET_ALARM				// Verificar modo editar alarma
	BREQ	SHOW_EDIT
	CPI		R16, SHOW_DATE				// Verificar modo mostrar fecha
	BREQ	SHOW_DATE_DISPLAY
	RJMP	SHOW_TIME_DISPLAY			// Por defecto mostramos la hora
	;----- MOSTRAR EDICIÓN -----;
	// Según MUX_INDEX, cargamos el dígito de edición que corresponde
SHOW_EDIT:
	CPI		R17, 0
	BRNE	EDIT1
	LDS		R18, EDIT_D1				// Display 0 -> dígito 1 de edición
	RJMP	LOAD_SEG
EDIT1:
	CPI		R17, 1
	BRNE	EDIT2
	LDS		R18, EDIT_D2				// Display 1 -> dígito 2 de edición
	RJMP	LOAD_SEG
EDIT2:
	CPI		R17, 2
	BRNE	EDIT3
	LDS		R18, EDIT_D3				// Display 2 -> dígito 3 de edición
	RJMP	LOAD_SEG
EDIT3:
	LDS		R18, EDIT_D4				// Display 3 -> dígito 4 de edición
	RJMP	LOAD_SEG
	;----- MOSTRAR ALARMA -----;
	// Misma lógica que SHOW_EDIT: según MUX_INDEX cargamos minuto/hora de alarma
SHOW_ALARM_DISPLAY:
	CPI		R17, 0
	BRNE	ALARM1
	LDS		R18, ALARM_MINU				// Unidades de minuto de alarma
	RJMP	LOAD_SEG
ALARM1:
	CPI		R17, 1
	BRNE	ALARM2
	LDS		R18, ALARM_MIND				// Decenas de minuto de alarma
	RJMP	LOAD_SEG
ALARM2:
	CPI		R17, 2
	BRNE	ALARM3
	LDS		R18, ALARM_HORU				// Unidades de hora de alarma
	RJMP	LOAD_SEG
ALARM3:
	LDS		R18, ALARM_HORD
	RJMP	LOAD_SEG
	;----- MOSTRAR HORA -----;
	// Misma lógica de selección por MUX_INDEX, ahora con contadores de tiempo real
SHOW_TIME_DISPLAY:
	CPI		R17, 0
	BRNE	TIME1
	LDS		R18, COUNTER_MINU			// Unidades de minuto
	RJMP	LOAD_SEG
TIME1:
	CPI		R17, 1
	BRNE	TIME2
	LDS		R18, COUNTER_MIND			// Decenas de minuto
	RJMP	LOAD_SEG
TIME2:
	CPI		R17, 2
	BRNE	TIME3
	LDS		R18, COUNTER_HORU			// Unidades de hora
	RJMP	LOAD_SEG
TIME3:
	LDS		R18, COUNTER_HORD			// Decenas de hora
	RJMP	LOAD_SEG
	;----- MOSTRAR FECHA -----;
	// Misma lógica, con contadores de día y mes
SHOW_DATE_DISPLAY:
	CPI		R17, 0
	BRNE	DATE1
	LDS		R18, COUNTER_MESU			// Unidades de mes
	RJMP	LOAD_SEG
DATE1:
	CPI		R17, 1
	BRNE	DATE2
	LDS		R18, COUNTER_MESD			// Decenas de mes
	RJMP	LOAD_SEG
DATE2:
	CPI		R17, 2
	BRNE	DATE3
	LDS		R18, COUNTER_DIAU			// Unidades de día
	RJMP	LOAD_SEG
DATE3:
	LDS		R18, COUNTER_DIAD			// Decenas de día

	;----- TABLA DE 7 SEGMENTOS -----;
LOAD_SEG:
	LDI		ZH, HIGH(table7seg<<1)		// Carga dirección base de la tabla
	LDI		ZL, LOW(table7seg<<1)
	ADD		ZL, R18						// Sumar el índice del dígito para apuntar al byte correcto
	LDI		R17, 0
	ADC		ZH, R17						// Propagar el carry al byte alto
	LPM		R16, Z						// Leer el patrón de segmento de la tabla
	;----- APLICAR DP -----;
	LDS		R18, FLAG_DP				// Cargamos la bandera del DP
	CPI		R18, 0
	BREQ	NO_DP						// Si la bandera es 0, no activamos DP
	ORI		R16, (1<<PD0)				// Si sí, activamoes el bit para el DP
NO_DP:
	OUT		PORTD, R16					// Si no hay DP, ya solo sacamos el segmento al puerto D

	;----- ENCENDER DISPLAY -----;
	// Activamos el pin de habilitación del display que corresponde al MUX_INDEX actual
	LDS		R17, MUX_INDEX
	CPI		R17, 0
	BREQ	EN0
	CPI		R17, 1
	BREQ	EN1
	CPI		R17, 2
	BREQ	EN2
	RJMP	EN3
EN0:
	SBI		PORTB, 0					// Encender display 0
	RJMP	NEXT_MUX
EN1:
	SBI		PORTB, 1					// Encender display 1
	RJMP	NEXT_MUX
EN2:
	SBI		PORTB, 2					// Encender display 2
	RJMP	NEXT_MUX
EN3:
	SBI		PORTB, 3					// Encender display 3
	// SIGUIENTE DISPLAY
NEXT_MUX:
	LDS		R17, MUX_INDEX
	INC		R17							// Avanzamos al siguiente display
	CPI		R17, 4
	BRLO	SAVE_MUX_INDEX				// Si llegó 1 4, reiniciamos
	CLR		R17
SAVE_MUX_INDEX:
	STS		MUX_INDEX, R17
	;----- SALIR -----;
	POP		R16
	OUT		SREG, R16					// Restauramos el SREG
	POP		ZL
	POP		ZH
	POP		R18
	POP		R17
	POP		R16
	RETI

/****************************************/
// ISR Timer1 - Marca cada minuto
TIMR1_ISR:
	PUSH	R16
	IN		R16, SREG
	PUSH	R16
	;----- RECARGAR TIMER1 -----;
	LDI		R16, HIGH(T1VALUE)
	STS		TCNT1H, R16
	LDI		R16, LOW(T1VALUE)
	STS		TCNT1L, R16
	;----- ACTIVAR BANDERA DE RELOJ -----;
	LDI		R16, 1
	STS		FLAG_CLK, R16				// Para señalizar al loop principal que pasó un minuto encendemos FLAG_CLK

	POP		R16
	OUT		SREG, R16
	POP		R16
	RETI

/****************************************/
// ISR Timer0 - Toggle punto decimal y LEDs de estado (~500ms)
TIMR0_ISR:
	PUSH	R16
	PUSH	R17
	IN		R16, SREG
	PUSH	R16
	;----- RECARGAR TIMER0 -----;
	LDI		R16, T0VALUE
	OUT		TCNT0, R16
	;----- INCREMENTAR CONTADOR DE 500ms -----;
	LDS		R16, COUNTER_OVF_CLK
	INC		R16
	CPI		R16, 2						// Cuando hayan pasado 2 overflow entonces llega a 500ms
	BRLO	SAVE_OVF_AND_EXIT			// Si no han pasado 500ms salimos

	CLR		R16
	STS		COUNTER_OVF_CLK, R16		// Reiniciamos el counter de overflows
	;----- Toggle FLAG_DP -----;
	LDS		R16, FLAG_DP
	LDI		R17, 1
	EOR		R16, R17					// XOR con 1, basicamente invierte el bit menos significativo logrando un toggle
	STS		FLAG_DP, R16
	MOV		R17, R16					// Guardar el valor de la bandera en R17 para las LEDs
	;----- CONTORLAR LEDS SEGÚN ESTADO ------;
	LDS		R16, STATE
	// SHOW_TIME
	CPI		R16, SHOW_TIME
	BRNE	T0_SHOW_DATE
	SBI		PORTB, 4					// LED4 fijo encendido
	CBI		PORTB, 5					// LED5 apagado
	RJMP	EXIT_TMR0_ISR
T0_SHOW_DATE:
	// SHOW_DATE
	CPI		R16, SHOW_DATE
	BRNE	T0_SET_TIME
	CBI		PORTB, 4					// LED4 apagado
	SBI		PORTB, 5					// LED5 fijo encendido
	RJMP	EXIT_TMR0_ISR
T0_SET_TIME:
	// SET_TIME
	CPI		R16, SET_TIME
	BRNE	T0_SET_DATE
	CBI		PORTB, 5
	TST		R17							// Comprueba si el registro es 0 (es como R17 AND R17)
	BREQ	T0_LED4_OFF
	SBI		PORTB, 4					// LED4 parpadea también cada 500ms
	RJMP	EXIT_TMR0_ISR
T0_LED4_OFF:
	CBI		PORTB, 4
	RJMP	EXIT_TMR0_ISR
T0_SET_DATE:
	// SET_DATE
	CPI		R16, SET_DATE
	BRNE	T0_SET_ALARM
	CBI		PORTB, 4
	TST		R17
	BREQ	T0_LED5_OFF
	SBI		PORTB, 5					// LED5 parpadea también cada 500ms
	RJMP	EXIT_TMR0_ISR
T0_LED5_OFF:
	CBI		PORTB, 5
	RJMP	EXIT_TMR0_ISR
T0_SET_ALARM:
	// SET_ALARM
	CPI		R16, SET_ALARM
	BRNE	T0_ALARM_RING
	SBI		PORTB, 4					// LED4 y LED5 fijas encendidas
	SBI		PORTB, 5
	RJMP	EXIT_TMR0_ISR
T0_ALARM_RING:
	// ALARM_RING
	CPI		R16, ALARM_RING
	BRNE	EXIT_TMR0_ISR
	TST		R17
	BREQ	T0_LEDS_OFF
	SBI		PORTB, 4					// LED4 y LED5 parpadeando cada 500ms
	SBI		PORTB, 5
	RJMP	EXIT_TMR0_ISR
T0_LEDS_OFF:
	CBI		PORTB, 4
	CBI		PORTB, 5
	RJMP	EXIT_TMR0_ISR
	;----- GUARDAR CONTADOR CUANDO AUN NO LLEGA A 2 -----;
SAVE_OVF_AND_EXIT:
	STS		COUNTER_OVF_CLK, R16
EXIT_TMR0_ISR:
	POP		R16
	OUT		SREG, R16
	POP		R17
	POP		R16
	RETI

/****************************************/
// ISR Pin Change - Manejo de botones (antirrebote físico)
PCINT_ISR:
	PUSH	R16
	PUSH	R17
	IN		R16, SREG
	PUSH	R16
	;----- LEER BOTONES -----;
	IN		R16, PINC
	COM		R16							// Invertir todos los bits: botones activos en bajo -> activos en alto
	ANDI	R16, 0x1F					// Mascara para solo los 5 bits de los botones

	TST		R16
	BREQ	PCINT_EARLY_EXIT			// Si ningún botón está presionado salimos
	RJMP	PCINT_CONTINUE
PCINT_EARLY_EXIT:						// Se añadió esta rutina aquí para que no estuviera fuera del rango del salto
	POP		R16
	OUT		SREG, R16
	POP		R17
	POP		R16
	RETI
PCINT_CONTINUE:
	;----- SI ALARMA SONANDO -----;
	// Cualquier botón apaga la alarma
	LDS		R16, STATE
	CPI		R16, ALARM_RING
	BRNE	CHECK_STATE
	CBI		PORTC, 5					// Apagar el buzzer (PC5)
	LDI		R16, SHOW_TIME
	STS		STATE, R16					// Volvemos al estado mostrar hora
	RJMP	EXIT_PCINT
	;----- CAMBIAR DE ESTADO (PC0) -----;
CHECK_STATE:
	SBIC	PINC, 0						// Saltar la siguiente instrucció si PC0 está presionado
	RJMP	CHECK_EDIT					// Si PC0 no está presionado revisamos revisar botones de edición 
	// PC0 presionado: si estamos en modo edición, giardar los datos antes de cambiar estado
	LDS		R16, STATE
	CPI		R16, SET_TIME
	BREQ	SAVE_TIME
	CPI		R16, SET_DATE
	BREQ	SAVE_DATE
	CPI		R16, SET_ALARM
	BREQ	SAVE_ALARM
	RJMP	NEXT_STATE
	;----- GUARDAR EN EDITAR SEGÚN ESTADO -----;
	// GUARDAR HORA
SAVE_TIME:								// Copiar dígitos editados a los contadores de hora
	LDS		R17, EDIT_D1
	STS		COUNTER_MINU, R17			// Unidades de minuto
	LDS		R17, EDIT_D2
	STS		COUNTER_MIND, R17			// Decenas de minuto
	LDS		R17, EDIT_D3
	STS		COUNTER_HORU, R17			// Unidades de hora
	LDS		R17, EDIT_D4
	STS		COUNTER_HORD, R17			// Decenas de hora
	RJMP	NEXT_STATE
	//GUARDAR FECHA
SAVE_DATE:								// Misma lógica que SAVE_TIME, pero para el día y mes
	LDS		R17, EDIT_D1
	STS		COUNTER_MESU, R17
	LDS		R17, EDIT_D2
	STS		COUNTER_MESD, R17
	LDS		R17, EDIT_D3
	STS		COUNTER_DIAU, R17
	LDS		R17, EDIT_D4
	STS		COUNTER_DIAD, R17
	RJMP	NEXT_STATE
	// GUARDAR ALARMA
SAVE_ALARM:								// Misma lógica que SAVE_TIME, pero para la alarma
	LDS		R17, EDIT_D1
	STS		ALARM_MINU, R17
	LDS		R17, EDIT_D2
	STS		ALARM_MIND, R17
	LDS		R17, EDIT_D3
	STS		ALARM_HORU, R17
	LDS		R17, EDIT_D4
	STS		ALARM_HORD, R17
	RJMP	NEXT_STATE

	;----- SIGUIENTE ESTADO -----;
NEXT_STATE:
	LDS		R16, STATE
	INC		R16							// Avanzamos de estado
	CPI		R16, 5
	BRLO	LOAD_EDIT_VARS
	LDI		R16, SHOW_TIME				// Si pasó del estado 4, volver al inicio (SHOW_TIME)
	;----- SUBIR VARIABLES DE SET A EDIT -----;
	// Al entrar a un modo SET, los valores reales se copian a EDIT_Dx para editarlos sin perder los originales
LOAD_EDIT_VARS:							// Verificar en qué estado de edición está, si no está en edición salimos
	STS		STATE, R16
	CPI		R16, SET_TIME
	BREQ	LOAD_TIME_TO_EDIT
	CPI		R16, SET_DATE
	BREQ	LOAD_DATE_TO_EDIT
	CPI		R16, SET_ALARM
	BREQ	LOAD_ALARM_TO_EDIT
	RJMP	EXIT_PCINT
LOAD_TIME_TO_EDIT:						// Copiar hora actual a las variables de edición
	LDS		R17, COUNTER_MINU
	STS		EDIT_D1, R17
	LDS		R17, COUNTER_MIND
	STS		EDIT_D2, R17
	LDS		R17, COUNTER_HORU
	STS		EDIT_D3, R17
	LDS		R17, COUNTER_HORD
	STS		EDIT_D4, R17
	RJMP	EXIT_PCINT
LOAD_DATE_TO_EDIT:						// Copiar fecha actual a las variables de edición
	LDS		R17, COUNTER_MESU
	STS		EDIT_D1, R17
	LDS		R17, COUNTER_MESD
	STS		EDIT_D2, R17
	LDS		R17, COUNTER_DIAU
	STS		EDIT_D3, R17
	LDS		R17, COUNTER_DIAD
	STS		EDIT_D4, R17
	RJMP	EXIT_PCINT
LOAD_ALARM_TO_EDIT:						// Copiar la alarma actual a las variables de edición
	LDS		R17, ALARM_MINU
	STS		EDIT_D1, R17
	LDS		R17, ALARM_MIND
	STS		EDIT_D2, R17
	LDS		R17, ALARM_HORU
	STS		EDIT_D3, R17
	LDS		R17, ALARM_HORD
	STS		EDIT_D4, R17
	RJMP	EXIT_PCINT
	
	;----- BOTONES DE EDICIÓN -----;
	// Solo sirven si el sistema está en algún modo de SET
CHECK_EDIT:
	LDS		R16, STATE
	CPI		R16, SET_TIME
	BREQ	SET_FLAG_TIME
	CPI		R16, SET_DATE
	BREQ	SET_FLAG_DATE
	CPI		R16, SET_ALARM
	BREQ	SET_FLAG_ALARM
	RJMP	EXIT_PCINT
SET_FLAG_TIME:
	LDI		R17, 1
	STS		FLAG_FIX_TIME, R17			// Indicar que la hora fue modificada
	RJMP	EDIT_DIGITS
SET_FLAG_DATE:
	LDI		R17, 1
	STS		FLAG_FIX_DATE, R17			// Indicar que la fecha fue modificada
	RJMP	EDIT_DIGITS
SET_FLAG_ALARM:
	LDI		R17, 1
	STS		FLAG_FIX_ALARM, R17			// Indicar que la alarma fue modificada
	;----- EDITAR DÍGITOS -----;
	// PC1: decrementa dígitos bajos (EDIT_D1) | PC2: incrementa | PC3: decrementa dígitos altos (EDIT_D3) | PC4: incrementa 
EDIT_DIGITS:
	SBIC	PINC, 1
	RJMP	CHECK_PC2					// Si PC1 no está presionado -> revisar PC2
	LDS		R16, EDIT_D1
	DEC		R16							// Decrementar unidades (minutos o mes)
	STS		EDIT_D1, R16
	RJMP	EXIT_PCINT
CHECK_PC2:
	SBIC	PINC, 2
	RJMP	CHECK_PC3
	LDS		R16, EDIT_D1
	INC		R16							// Incrementar unidades
	STS		EDIT_D1, R16
	RJMP	EXIT_PCINT
CHECK_PC3:
	SBIC	PINC, 3
	RJMP	CHECK_PC4
	LDS		R16, EDIT_D3
	DEC		R16							// Decrementar decenas (horas o días)
	STS		EDIT_D3, R16
	RJMP	EXIT_PCINT
CHECK_PC4:
	SBIC	PINC, 4
	RJMP	EXIT_PCINT
	LDS		R16, EDIT_D3
	INC		R16							// Incrementar decenas
	STS		EDIT_D3, R16
EXIT_PCINT:
	POP		R16
	OUT		SREG, R16
	POP		R17
	POP		R16
	RETI

/****************************************/
// Tabla de segmentos (anodo comun o catodo comun segun hardware)
// 0    1     2     3     4     5     6     7     8     9
table7seg: .DB 0xEE, 0x82, 0xDC, 0xD6, 0xB2, 0x76, 0x7E, 0xC2, 0xFE, 0xF6