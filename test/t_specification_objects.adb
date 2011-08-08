with X_Specification_Objects;
with Calendar;
procedure T_specification_objects is
   type Rec is
      record
         V : Integer;
      end record;
   type Acc is access Rec;

   Local : Integer;

   generic
      X : Integer;
   package Gen is
      Y1 : Integer := 0;
      Y2 : Integer;
      Y3 : Integer := 0;
      Z : constant Integer := 1;
      function "+" (Left : in Calendar.Time;
                    Right : in Duration) return Calendar.Time
        renames Calendar."+";
   end Gen;

   package body Gen is
   begin
      Gen.Y2 := X;
   end Gen;

   package Inst1 is new Gen (0);
   package Inst2 is new Gen (1);

   package Pack is
      A1, A2 : Integer;
      A3 : Integer range 1..10 := 1;
      A4 : Integer range 1..10;
      B : constant Integer := 1;
      C : Integer renames A1;
      D,E,F : Integer;

      I1 : constant := 1;
      I2 : constant := 2;
      R : constant := 3.0;

      VR : Rec;
      Ac : Acc;

      type Arr_Acc is array (1..10) of Acc;
      type Arr_Arr_Acc is array (1..10) of Arr_Acc;
      V1 : Acc;
      Const : constant Acc := new Rec;
      V2 : Arr_Acc;
      V3 : Arr_Arr_Acc;
      Y : array (1..10) of Arr_Acc;
      Z : array (1..10) of Arr_Acc;

      -- Some nasty subtypes and/or derived types...
      V4 : Natural;
      type Acc_Int is access Integer;
      type Derived is new Acc;
      V5 : Derived;
   private
      XX : Integer;
   end Pack;
   use Pack;

   procedure P (X : Integer; Y : out Integer; Z : in out Integer) is
   begin
      null;
   end P;

   -- Special case for access types
-- This check disabled because of ASIS failure
--     generic
--        with package P1 is new Gen (0);
--        with package P2 is new Gen (<>);
--     package Gen_Gen is end Gen_Gen;

--     package body Gen_Gen is
--     begin
--        P1.Y1 := P2.Y3;
--     end Gen_Gen;

--     package Inst_Inst is new Gen_Gen (Inst1, Inst2);
begin
   Ac.V := 0;            -- Read of Ac

   Pack.VR.V := 1;       -- Write of VR
   Pack.A1 := Pack.A3;   -- Write of Pack.A1, Read of Pack.A3
   A2 := C;              -- Write of Pack.A2, Read of Pack.A1
   A2 := I2;
   Const.V := 1;         -- A constant on the LHS
   P (D, E, F);
   Inst1.Y1 := Inst2.Y3;

   X_specification_objects.Not_Included := 0;
end T_specification_objects;
