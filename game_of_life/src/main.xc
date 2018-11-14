// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define INPUT_IMAGE "64x64.pgm"
#define  IMHT 64                  //image height
#define  IMWD 64                  //image width
#define NUM_ROUNDS 47

#define ALIVE 255
#define DEAD 0

//#define DEBUG_PRINTS

typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;
in port buttons = XS1_PORT_4E;
out port leds = XS1_PORT_4F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6


void showLEDs(out port p, int pattern) {
    //1st bit...separate green LED
    //2nd bit...blue LED
    //3rd bit...green LED
    //4th bit...red LED
    p <: pattern;
}


void buttonListener(in port b, chanend toDistributor) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))     // if either button is pressed
    toDistributor <: r;         // send button pattern to userAnt
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void readImage(char infname[], uchar board[IMHT][IMWD])
{
  int res;
  uchar line[ IMWD ];
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ ) {
        board[y][x] = line[x];
#ifdef DEBUG_PRINTS
        printf( "-%4.1d ", line[ x ] ); //show image values
#endif
    }
#ifdef DEBUG_PRINTS
    printf( "\n" );
#endif
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

int modulo(int a, int b) {
  const int result = a % b;
  return result >= 0 ? result : result + b;
}

int getLiveNeighbours(int x, int y, uchar board[IMHT][IMWD]) {
    int liveNeighbours = 0;

    for (int i = x - 1; i <= x + 1; i++) {
        for (int j = y - 1; j <= y + 1; j++) {
            if (!(i == x && j == y)) { // do not count the pixel itself
                int neighbourX = modulo(i, IMWD);
                int neighbourY = modulo(j, IMHT);

                if (board[neighbourY][neighbourX] == ALIVE) liveNeighbours++;
            }
        }
    }

    return liveNeighbours;
}

uchar nextPixel(int liveNeighbours, uchar currentPixel) {
    if (currentPixel == ALIVE) {
        if (liveNeighbours < 2) return DEAD;
        else if (liveNeighbours > 3) return DEAD;
    }
    else if (currentPixel == DEAD && liveNeighbours == 3) return ALIVE;

    return currentPixel;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void writeImage(char outfname[], uchar board[IMHT][IMWD])
{
  int res;
  uchar line[ IMWD ];

  //Open PGM file
  printf( "DataOutStream: Start...\n" );

  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      line[x] = board[y][x];
    }
    _writeoutline( line, IMWD );
#ifdef DEBUG_PRINTS
    printf( "DataOutStream: Line written...\n" );
#endif
  }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );

  return;
}

void exportBoard(uchar board[IMHT][IMWD], int round) {
    showLEDs(leds, 0b1000);

    char fileName[64];
    sprintf(fileName, "out_%d.pgm", round);
    writeImage(fileName, board);
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend fromAcc, chanend fromButtons)
{
  uchar boards[2][IMHT][IMWD];

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

  printf("Waiting for read button press to begin...\n");
  int button;
  fromButtons :> button;
  while (button != 14) {
      fromButtons :> button;
  }

  //Read in and do something with your image values..
  //This just inverts every pixel, but you should
  //change the image according to the "Game of Life"
  printf( "Processing...\n" );
  showLEDs(leds, 0b0100);
  readImage("64x64.pgm", boards[0]);

  int round = 0;
  while (round < NUM_ROUNDS) {
      int currentLED = 0b0000;

      select {
          case fromAcc :> int tilted:
              if (currentLED != (0b0010 | round % 2)) {
                  currentLED = 0b0010 | round % 2;
                  showLEDs(leds, currentLED);
              }

              fromAcc :> tilted;

              break;

          case fromButtons :> int button:
              if (button == 13) {
                  exportBoard(boards[round % 2], round);
              }

              break;

          default:
              showLEDs(leds, round % 2);
              for( int y = 0; y < IMHT; y++ ) {   //go through all lines
                  for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line                   //read the pixel value
                      int boardNo = round % 2;
                      int liveNeighbours = getLiveNeighbours(x, y, boards[boardNo]);

                      boards[(round + 1) % 2][y][x] = nextPixel(liveNeighbours, boards[boardNo][y][x]);
                  }
              }
              ++round;

              break;

      }

      printf("Turn %d complete\n", round);
  }

  exportBoard(boards[round % 2], round);
  showLEDs(leds, 0b0000);

  printf( "\nDone.\n" );
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }
  
  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt
    if (x > 30) {
        toDist <: 1;
        while (x > 30) {
            //get new x-axis tilt value
            x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);
        }

        toDist <: 0;
    }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

chan c_control, c_distribButtons;    //extend your channel definitions here

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0],c_control);        //client thread reading orientation data
    distributor(c_control, c_distribButtons);//thread to coordinate work on image
    buttonListener(buttons, c_distribButtons);
  }

  return 0;
}
