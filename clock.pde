#include <plib.h>
//#include <SPI.h>
//#include <Ethernet.h>

//byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
//byte ip[] = { 192,168,1, 177 };
//Server server(8000);

const unsigned int max_instructions = 200;
int autostart;
unsigned int instructions[max_instructions];


void __attribute__((noinline)) run(){
  // don't fill our branch delay slots with nops, thank you very much.
  // Also declare that we're using all these registers, so that we don't corrupt the rest of the program:
  asm volatile (".set noreorder\n\t":::"t0","t1","t2","t3","t4", "t5", "t6", "t7", "k0", "k1", "v0", "v1");
  // get ready to start the instruction interpreter:
  // load the ram address of PR2 into register $t0:
  asm volatile ("la $t0, PR2\n\t");
  // load the ram address of OC2R into register $t1:
  asm volatile ("la $t1, OC2R\n\t");
  // load the address of the instruction array into register $t2:
  asm volatile ("la $t2, instructions\n\t");
  // load the period into register $t3:
  asm volatile ("lw $t3, 0($t2)\n\t"); 
  // load the delay time into register $t4:
  asm volatile ("lw $t4, 4($t2)\n\t"); 
  // load the the autostart flag into register $t5:
  asm volatile ("la $t5, autostart\n\t");
  asm volatile ("lw $t5, 0($t5)\n\t");
  // load the address of IPC0 into register $t5:
  asm volatile ("la $t6, IPC0\n\t");
  // load the address of OC2CON into register $t7
  asm volatile ("la $t7, OC2CON\n\t");
  
  
  // if we're set to autostart, prepare for that:
  asm volatile ("beq $t5, $zero, hwstart\n\t");
  asm volatile ("nop\n\t");
  // disable the hardware trigger by setting IPC0 to zero:
  asm volatile ("sw $zero, 0($t6)\n\t");
  // enable global interrupts:
  asm volatile ("ei\n\t");
  // run the interpreter.
  // It will 'jr $ra' when done, so we don't need to put a return here:
  asm volatile ("j interpreter\n\t");
  asm volatile ("nop\n\t");


  // otherwise, prepare for a hardware trigger:
  asm volatile ("hwstart:\n\t");
  // the Status we need to write to acknowledge that we're servicing the interrupt
  asm volatile ("li $k0, 0x101001\n\t");
  // The Status we need to write to say we've finished the interrupt
  asm volatile ("li $k1, 0x100003\n\t");
  // the address of IFS0
  asm volatile ("la $v0, IFS0\n\t");
  // the value of IFSO we need to write to say we've finished the interrupt
  asm volatile ("li $v1, 0x10088880\n\t");
  // enable global interrupts:
  asm volatile ("ei\n\t");
  // wait for a trigger:
  asm volatile ("wait\n\t");
  // The interrupt will cause a jump to the interpreter.
  // When it finishes, we'll end up back here. So return:
  asm volatile ("jr $ra\n\t");
  asm volatile ("nop\n\t");

}

void __attribute__((naked, at_vector(3), nomips16)) ExtInt0Handler(void){
  // This function gets called when a hardware trigger is received:
  asm volatile (".set noreorder\n\t");
  asm volatile ("j interpreter\n\t");
  asm volatile ("mtc0	$k0, $12\n\t"); // Status to indicate we've started servicing the interrupt:
}

void __attribute__((naked, nomips16)) Interpreter(){
  asm volatile (".set noreorder\n\t");
  // update the period of the output:
  asm volatile ("interpreter: sw $t3, 0($t0)\n\t"); 
  asm volatile ("sw $t3, 0($t1)\n\t");
  // wiat for the delay time:
  asm volatile ("wait_loop: bne $t4, $zero, wait_loop\n\t");
  asm volatile ("addi $t4, -1\n\t");
  // load the next period in:
  asm volatile ("lw $t3, 8($t2)\n\t");
  // increment our instruction pointer:
  asm volatile ("addi $t2, 8\n\t");
  // go to the top of the loop if it's not a stop instruction:
  asm volatile ("bne $t3, $zero, interpreter\n\t");
  // load the the next delay time in:
  asm volatile ("lw $t4, 4($t2)\n\t");
  
  // turn the output compare module off:
  asm volatile ("sw $zero, 0($t7)");
  
  // if this was an autostarted run, return:
  asm volatile ("beq $t5, $zero, hwstart_finalisation\n\t");
  asm volatile ("nop\n\t");
  asm volatile ("jr $ra\n\t");
  asm volatile ("nop\n\t");
  
  // otherwise, finalise the interrupt which we are presently in:
  // write the required IFS0 indicating we've handled the interrupt:
  asm volatile ("hwstart_finalisation:");
  asm volatile ("sw $v1, 0($v0)\n\t");
  // Write the required Status indicating we've handled the interrupt:
  asm volatile ("mtc0	$k1, $12\n\t"); // restore Status
  // return to just after the wait instruction where the interrupt occured:
  asm volatile ("eret\n\t");
}


void start(){
  // turn off global interrupts while we manipulate interrupts settings.
  // They will be re-enabled in run():
  noInterrupts();
  
  // keep a backup of the interrupt priorities, so we can restore them after run():
  int temp_IPC0 = IPC0;
  int temp_IPC6 = IPC6;
  
  // set all interrupt priorities to zero:
  IPC0 = 0;
  IPC6 = 0;

  // Attach our hardware trigger interrupt (this makes its priority nonzero):
  attachInterrupt(0,0,RISING);
  
  // setupt pulse widthe modulation:
  // set the timer to 32 bit mode, no prescaler, and disable it:
  T2CON = 0x0008;
  // disable the output compare module:
  OC2CON = 0x0000; 
  // set to invert on compare:
  OC2CON = 0x0023; 
  // set the timer period and compare value to zero:
  OC2R = 0;
  PR2 = 0;
  // set the two registers for the timer to zero:
  TMR2 = 0;
  TMR3 = 0;
  asm volatile ("nop\n\t");
  // start the timer:
  T2CONSET = 0x8000; 
  // start the output compare module:
  OC2CONSET = 0x8000; 
  
  // ready to roll:
  Serial.println("ok");
  run();
  
  // Restore other interrupts to their previous state:
  IPC0 = temp_IPC0;
  IPC6 = temp_IPC6;
}


String readline(){
  String readstring = "";
  char c;
  byte crfound = 0;
  while (true){
    if (Serial.available() > 0){
      char c = Serial.read();
      if (c == '\r'){
        crfound = 1;
      }
      else if (c == '\n'){
        if (crfound == 1){
          return readstring;
        }
        else{
          readstring += '\n';
        }
      }
      else if (crfound){
        crfound = 0;
        readstring += '\r';
        readstring += c;
      }
      else{
        readstring += c;
      }
    }
  }
}

void setup(){
  // start the Ethernet connection and the server:
  //Ethernet.begin(mac, ip);
  //server.begin();
  Serial.begin(115200);
  int i = 0;
  for (i=0;i<86;i++){
    pinMode(i, OUTPUT);
    digitalWrite(i,LOW);
  }
}

void loop(){

  Serial.println("in mainloop!");
  String readstring = readline();
  if (readstring == "hello"){
    Serial.println("hello");
  }
  else if (readstring == "hwstart"){
    autostart = 0;
    start();
  }
  else if ((readstring == "start") || (readstring == "")){
    autostart = 1;
    start();
  }
  else if (readstring.startsWith("set ")){
    int firstspace = readstring.indexOf(' ');;
    int secondspace = readstring.indexOf(' ', firstspace+1);
    int thirdspace = readstring.indexOf(' ', secondspace+1);
    if (secondspace == -1 || thirdspace == -1){
      Serial.println("invalid request");
      return;
    }
    unsigned int addr = readstring.substring(firstspace+1, secondspace).toInt();
    unsigned int delay_time = readstring.substring(secondspace+1, thirdspace).toInt();
    unsigned int reps = readstring.substring(thirdspace+1).toInt();
    if (addr >= max_instructions){
      Serial.println("invalid address");
    }
    else if (delay_time < 4){
      Serial.println("period too short");
    }
    else{
      instructions[2*addr] = delay_time - 1;
      instructions[2*addr+1] = delay_time*reps - 4;
      Serial.println("ok");
    }
  }
  else if (readstring == "go high"){
    digitalWrite(5,HIGH);
    Serial.println("ok");
  }
  else if (readstring == "go low"){
    digitalWrite(5,LOW);
    Serial.println("ok");
  }
  
  else{
    Serial.println("invalid request");
  }
}


