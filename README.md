## How to install

Go to the ```src``` directory.  Inside it there is a ```makefile```.  You may
edit it for your own needs (but you don't have to).  Then run
```bash
    make
```
and an executable file with default name ```a.out``` will be generated in the
same directory.


## How to run the code

There are a few input data files that are needed for the code to run.

The following files are compulsary:
    1. Configuration file.
    2. Chemical network.
    3. Initial chemical composition.

The following files are optional:
    1. Density structure.
    2. Enthalpy of formation of species.
    3. Transition data of molecules.
    4. Stellar spectrum.
    5. Points to output the intermediate steps of chemcial evolution.
    6. Species to output the intermediate steps of chemcial evolution.
    7. Species to check for grid refinement.

Go to the ```inp``` directory.  Edit the file ```configure.dat```.  It has
nearly 200 entries.  Some of them are for setting up the physics and chemistry
of the model, some are for setting up the running environment, while others are
switches telling the code whether or not it should execute some specific tasks.
Details for editing the configure file is included below.

After you have get the configre file ready
