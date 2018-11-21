////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// GAME OF LIFE ///////////////////////////////////
////////////////////// Jack Bond-Preston & Kai Hulme ///////////////////////////
////////////////////////////////////////////////////////////////////////////////

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

//////////// IMAGE SIZE, No. of WORKERS, No. of ROUNDS & DEBUGGING /////////////

#define INPUT_IMAGE "512x512.pgm"   // image for processing
#define IMHT 512                    // image height
#define IMWD 512                    // image width

#define NUM_ROUNDS 100              // number of processing rounds
#define NUM_WORKERS 4               // number of worker threads

//#define DEBUG_PRINTS              // print statements for debugging

////////////////////////////////////////////////////////////////////////////////

#define WKHT (IMHT / NUM_WORKERS)   // height of worker boards

#if (IMWD >= 32)                    // define int size for bit packing...
    typedef uint32_t b_int;         // ... depending on input image size
    #define INT_SIZE 32
#elif (IMWD >= 16)
    typedef uint16_t b_int;
    #define INT_SIZE 16
#endif

#define WKWD (IMWD / INT_SIZE)      // width of worker boards

#define ALIVE 255                   // def for alive cells
#define DEAD 0                      // def for dead cells

typedef unsigned char uchar;        // using uchar as shorthand

////////////////////////////////////////////////////////////////////////////////

/************** INTERFACE PORTS FOR XMOS xCORE 200 EXPLORER KIT ***************/

#define FXOS8700EQ_I2C_ADDR 0x1E
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

on tile[0]: port p_scl = XS1_PORT_1E;         // interface ports for orientation
on tile[0]: port p_sda = XS1_PORT_1F;
on tile[0]: in port buttons = XS1_PORT_4E;    // interface ports for buttons
on tile[0]: out port leds = XS1_PORT_4F;      // interface ports for LEDs

////////////////////////////////////////////////////////////////////////////////

/******************************************************************************/
/************************ GAME OF LIFE IMPLEMENTATION *************************/
/******************************************************************************/

/****************************** BIT PACKING ***********************************/

// sets an individual cell in a packed b_int
// takes the original b_int, the cell value and the position of the cell in this b_int
// returns the new b_int value
b_int setCell(b_int input, uchar cell, int pos) {

    int bit = (cell == ALIVE);
    return input | bit << pos;

}

// packs an entire b_int in one go from an array of cells
b_int setCells(uchar cells[INT_SIZE]) {

    b_int result = 0;

    for (int i = 0; i < INT_SIZE; i++) {
        uchar cell = cells[i];
        result = setCell(result, cell, i);
    }

    return result;

}

// gets the value of a cell from a packed b_int at a given position in this b_int
uchar getCell(b_int data, int pos) {

    return ((data & (1 << pos)) != 0) * 255;

}

// puts an entire b_ints cells into the given array of cells
void getCells(b_int data, uchar result[INT_SIZE]) {

    for (int i = 0; i < INT_SIZE; i++) {
        result[i] = getCell(data, i);
    }

}

////////////////////////////////////////////////////////////////////////////////

/************************ IMAGE READING AND WRITING ***************************/

// function for reading in pgm image file
void readImage(char infname[], b_int board[IMHT][WKWD]) {

    int res;
    uchar line[ IMWD ];

    printf("Reading file: %s...\n", infname);

    res = _openinpgm( infname, IMWD, IMHT ); // open PGM file
    if(res) {
        printf("Error openening file %s\n.", infname);
        return;
    }

    // read image line-by-line and send byte by byte to channel c_out
    for(int y=0; y<IMHT; y++) {

    _readinline( line, IMWD );

        for (int x = 0; x < WKWD; x++) {
            b_int packed = 0;
            for (int i = 0; i < INT_SIZE; i++) {
                packed = setCell(packed, line[x * INT_SIZE + i], i);
            }
            board[y][x] = packed;


            #ifdef DEBUG_PRINTS
                printf("%u ", packed); //show image values
            #endif
        }
        #ifdef DEBUG_PRINTS
            printf("\n");
        #endif
    }

    _closeinpgm(); // close PGM image file
    printf("File read.\n");

    return;
}

// function for writing image pgm image file
void writeImage(char outfname[], b_int board[IMHT][WKWD]) {
    int res;

    printf("Writing to file %s...\n", outfname);

    res = _openoutpgm(outfname, IMWD, IMHT); // open PGM file
    if(res) {
        printf("Error opening %s\n.", outfname);
        return;
    }

    // compile each line of the image and write the image line-by-line
    for(int y = 0; y < IMHT; y++) {
        uchar line[ IMWD ];

        for (int x = 0; x < WKWD; x++) {
            b_int packed = board[y][x];

            #ifdef DEBUG_PRINTS
                printf("%u ", packed);
            #endif

            for (int i = 0; i < INT_SIZE; i++) {
                line[(x * INT_SIZE) + i] = getCell(packed, i);
            }
        }

        #ifdef DEBUG_PRINTS
            printf("\n");
        #endif

        _writeoutline(line, IMWD);

    }

    _closeoutpgm(); // close PGM file
    printf("Successfully written to file.");

    return;
}

// function for calling functions needed to write new PGM file
void exportBoard(b_int board[IMHT][WKWD], int round) {

    showLEDs(leds, 0b1000);                   // shows blue LED when writing
    char fileName[64];
    sprintf(fileName, "%d_%s", round, INPUT_IMAGE);   // creates a file name for current round
    writeImage(fileName, board);              // writes image to PGM file

}

////////////////////////////////////////////////////////////////////////////////

/***************************** LED PATTERNS ***********************************/

// function for sending LED pattern to board
void showLEDs(out port p, int pattern) {

    p <: pattern;   // bits represent LEDs: 1111 ~ green|blue|green|red

}

////////////////////////////////////////////////////////////////////////////////

/************************ START AND END FUNCTIONS *****************************/

// waits for SW1 button to be pressed
int startButtonPressed(chanend fromButtons) {
    int button;
    fromButtons :> button;      // gets button press
    while (button != 14) {      // if button press is not SW1 ...
      fromButtons :> button;    // ... wait for button SW1 press
    }
    return 1;
}

// deals with final function calls after processing rounds have completed
void endGame(chanend fromTiming, round) {
  exportBoard(board, round);
  showLEDs(leds, 0b0000);

  fromTiming <: 0;
  float totalTime;
  fromTiming :> totalTime;
  printf( "\nDone (total time: %f, average: %f).\n", totalTime, totalTime / NUM_ROUNDS);

  return;
}

////////////////////////////////////////////////////////////////////////////////

/**************************** GAME OF LIFE RULES ******************************/

// returns a mod b, works as intended with negative numbers
int modulo(int a, int b) {
    const int result = a % b;
    return result >= 0 ? result : result + b;
}

// gets the number of alive neighbours for a given cell
int getLiveNeighbours(int x, int y, b_int board[WKHT + 2][WKWD]) {

    int liveNeighbours = 0;

    // go from one before the cell to one after
    for (int i = x - 1; i <= x + 1; i++) {
        for (int j = y - 1; j <= y + 1; j++) {
            if (!(i == x && j == y)) { // do not count the cell itself
                int neighbourX = modulo(i, IMWD); // modulus used to allow wrapping around
                int neighbourY = j; // modulus not needed due to extra rows being above and below always

                int packedLocation = neighbourX / INT_SIZE;

                if (getCell(board[neighbourY][packedLocation], neighbourX % INT_SIZE) == ALIVE)
                    liveNeighbours++;
            }
        }
    }
    return liveNeighbours;

}

// works out next state for given pixel according to game of life rules
uchar nextPixel(int liveNeighbours, uchar currentPixel) {

    if (currentPixel == ALIVE) {
        if (liveNeighbours < 2) return DEAD;
        else if (liveNeighbours > 3) return DEAD;
    }
    else if (currentPixel == DEAD && liveNeighbours == 3) return ALIVE;

    return currentPixel;

}

////////////////////////////////////////////////////////////////////////////////

/***************************** ROUND PROCESSES ********************************/

// splits up the board for workers
void splitBoard(chanend toWorkers[NUM_WORKERS], b_int board[IMHT][WKWD]) {
    for (int i = 0; i < NUM_WORKERS; i++) {
        int start_row = (i * WKHT) - 1;
        int end_row = (i + 1) * WKHT;

        for (int row = start_row; row <= end_row; row++) {
            for (int colBit = 0; colBit < WKWD; colBit++) {
                toWorkers[i] <: board[modulo(row, IMHT)][colBit];
            }
        }
    }
}

// distributes work between each worker
void defaultRoundProcessing(chanend fromTiming, chanend toWorkers[NUM_WORKERS], int round) {

  fromTiming <: 1;
  showLEDs(leds, round % 2);

  splitBoard(toWorkers, board);

  for (int row = 0; row < WKHT; row++) {
      for (int col = 0; col < WKWD; col++) {
          for (int worker = 0; worker < NUM_WORKERS; worker++) {
              b_int z = 0;
              toWorkers[worker] :> z;
              board[row + (WKHT * worker)][col] = z;
          }
      }
  }

  ++round;

  fromTiming <: 1;

  float roundTime;
  fromTiming :> roundTime;

  printf("Turn %d complete in %f\n", round, roundTime);

  return;

}

// deals with board being tilted during round processing
void tiltedDuringProcessing(chanend fromAcc, int round, int currentLED, int tilted) {
    if (currentLED != (0b0010 | round % 2)) {
        currentLED = 0b0010 | round % 2;
        showLEDs(leds, currentLED);
    }
    fromAcc :> tilted;
    return;
}

// deals with buttons being pressed furing round processing
void buttonPressedDuringProcessing(int button, int round) {
    if (button == 13) exportBoard(board, round);
    return;
}

////////////////////////////////////////////////////////////////////////////////

/**************************** PARALLEL FUNCTIONS ******************************/

// sets up round processing
void distributor(chanend fromAcc, chanend fromButtons, chanend toWorkers[NUM_WORKERS], chanend fromTiming) {

    // start up and wait for button SW1 press
    printf("Waiting for read button press to begin...\n");
    while (!startButtonPressed(fromButtons)) continue;
    /*
    int button;
    fromButtons :> button;      // gets button press
    while (button != 14) {      // if button press is not SW1 ...
      fromButtons :> button;  // ... wait for button SW1 press
    }
    */

    // set board size and read PGM image to board array
    b_int board[IMHT][WKWD];
    readImage(INPUT_IMAGE, board);
    printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );

    // begin processing
    printf( "Processing...\n" );
    showLEDs(leds, 0b0100);             // shows green LED while processing
    int round = 0;                      // set initial round counter to 0

    // round processing
    while (round < NUM_ROUNDS) {

      int currentLED = 0b0000;

      select {

          case fromAcc :> int tilted:

              /*
              if (currentLED != (0b0010 | round % 2)) {
                  currentLED = 0b0010 | round % 2;
                  showLEDs(leds, currentLED);
              }

              fromAcc :> tilted;
              */

              tiltedDuringProcessing(fromAcc, currentLED, tilted);
              break;

          case fromButtons :> int button:

              // if (button == 13) exportBoard(board, round);

              buttonPressedDuringProcessing(button, round);
              break;

          default:

              /*
              fromTiming <: 1;
              showLEDs(leds, round % 2);

              splitBoard(toWorkers, board);

              for (int row = 0; row < WKHT; row++) {
                  for (int col = 0; col < WKWD; col++) {
                      for (int worker = 0; worker < NUM_WORKERS; worker++) {
                          b_int z = 0;
                          toWorkers[worker] :> z;
                          board[row + (WKHT * worker)][col] = z;
                      }
                  }
              }

              ++round;

              fromTiming <: 1;

              float roundTime;
              fromTiming :> roundTime;

              printf("Turn %d complete in %f\n", round, roundTime);
              */

              defaultRoundProcessing(fromTiming, toWorkers, round);
              break;

      }

    }

    endGame(fromTiming, round);

    /*
    exportBoard(board, round);
    showLEDs(leds, 0b0000);

    fromTiming <: 0;
    float totalTime;
    fromTiming :> totalTime;
    printf( "\nDone (total time: %f, average: %f).\n", totalTime, totalTime / NUM_ROUNDS);
    */

}

// completes game of life tules on a given section of the board
void worker(chanend fromDistributor) {
    for (int round = 0; round < NUM_ROUNDS; round++) {
        b_int board[WKHT + 2][WKWD];

        for (int row = 0; row < WKHT + 2; row++) {
            for (int col = 0; col < WKWD; col++) {
                fromDistributor :> board[row][col];
            }
        }

        for (int row = 1; row < WKHT + 1; row++) {
            for (int col = 0; col < WKWD; col++) {
                uchar line[INT_SIZE];

                for (int i = 0; i < INT_SIZE; i++) {
                    int liveNeighbours = getLiveNeighbours((col * INT_SIZE) + i, row, board);

                    uchar next = nextPixel(liveNeighbours, getCell(board[row][col], i));

                    if (next != ALIVE && next != DEAD) {
                        printf("malformed value: %d\n", next);
                    }

                    line[i] = next;
                }

                fromDistributor <: setCells(line);
            }
        }

    }
}

// listens for button presses on the board
void buttonListener(in port b, chanend toDistributor) {

    int r;

    while (1) {
        b when pinseq(15)  :> r;    // check that no button is pressed
        b when pinsneq(15) :> r;    // check if some buttons are pressed
        if ((r==13) || (r==14)) {   // if either button is pressed
            toDistributor <: r;       // send button pattern to userAnt
        }
    }

}

// listens to board orientation
void orientation (client interface i2c_master_if i2c, chanend toDist) {

    i2c_regop_res_t result;
    char status_data = 0;

    // configure FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
    if (result != I2C_REGOP_SUCCESS) printf("I2C write reg failed\n");

    // enable FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
    if (result != I2C_REGOP_SUCCESS) printf("I2C write reg failed\n");

    // probe the orientation x-axis forever
    while (1) {
        // check until new orientation data is available
        do {
          status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);

        // get new x-axis tilt value
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        // send signal to distributor after first tilt
        if (x > 30) {
            toDist <: 1;
            while (x > 30) {
                x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB); // get new x-axis tilt value
            }
            toDist <: 0;
        }
    }
}

// allows for processing time to be monitored
void timing(chanend fromDistributor) {
    timer t;
    int timerOn = 1;
    float roundTime;
    float totalTime = 0.0f;
    float period = 100000000;

    while (timerOn) {
        fromDistributor :> timerOn;

        if (!timerOn) {
            // rounds are complete, send total round time
            fromDistributor <: totalTime;
        }
        else {
            uint32_t startTime, endTime;

            t :> startTime;
            fromDistributor :> timerOn;
            t :> endTime;

            roundTime = (endTime - startTime) / period;
            fromDistributor <: roundTime;
            totalTime += roundTime;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////

/************************** PARALLEL DISTRIBUTION *****************************/

// main function for concurrent orchestration of functions
int main(void) {
    i2c_master_if i2c[1];               // interface to orientation
    chan c_control, c_distribButtons, c_distribWorkers[NUM_WORKERS], c_timing;   // channel definitions

    par {
        on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);         //server thread providing orientation data
        on tile[0]: orientation(i2c[0],c_control);                //client thread reading orientation data
        on tile[0]: buttonListener(buttons, c_distribButtons);

        on tile[1]: timing(c_timing);
        on tile[0]: distributor(c_control, c_distribButtons, c_distribWorkers, c_timing);     //thread to coordinate work on image
        par (int w = 0; w < NUM_WORKERS; w++) {
            on tile[w % 2]: worker(c_distribWorkers[w]);
        }
    }

    return 0;
}

////////////////////////////////////////////////////////////////////////////////
