separate (T_Simplifiable_Statements)
----------------------------
-- Test_For_In_For_For_Of --
----------------------------

procedure Test_For_In_For_For_Of is
   S1 : String (1 .. 10);
   S2 : String (1 .. 10);
   X  : Character;
   type Acc_Str is access String;
   Ptr : Acc_Str;
   Mat : array (1 .. 5, 1 .. 5) of Boolean;
begin
   L1 : for I in S1'Range loop         -- for_in_for_for_of
      X := S1 (I);
      X := S1 (I);
      X := S1 (L1.I);
      declare
         Inx : Integer renames I;
      begin
         X := S1 (Inx);
      end;
   end loop L1;

   for I in S1'Range loop              -- Not enough indexings
      X := S1(I);
   end loop;

   for I in 1 .. 9 loop                -- Index used in expression
      X := S1 (I + 1);
   end loop;

   for I in Ptr.all'Range loop         -- Indexing of dereference
      X := Ptr.all (I);
   end loop;

   for I in Integer range 1 .. 10 loop -- Different variables
      X := S1 (I);
      X := S2 (I);
   end loop;

   for I in S1'Range loop              -- Renaming, used with different variable
      X := S1 (I);
      declare
         Inx : Integer renames I;
      begin
         X := S2 (Inx);
      end;
   end loop;

   for I in 1 .. 10 loop               -- No indexing
      null;
   end loop;


   declare                             -- Same component of different variables
      type Rec is
         record
            Tab : String (1 .. 10);
         end record;
      V1, V2 : Rec;
   begin
      for I in V1.Tab'Range loop       -- for_for_slice
         V1.Tab (I) := V2.Tab (I);
      end loop;
   end;

   declare                             -- Indexing of function call
      function F return String is ("ABCD");
      C :  constant String := "ABCD";
   begin
      for I in 1 .. 3 loop
         X := F (I);
      end loop;
      for I in 1 .. 3 loop             -- for_in_for_for_of
         X := C (I);
         X := C (I);
      end loop;
   end;

   declare                             -- Case of arrays that depend on discriminants (5.5.2(6.1/4))
      subtype Inx is Natural range 0 .. 10;
      type Rec1 (L : Inx) is           -- No default value: OK
         record
            S : String (1 .. L);
         end record;
      type Rec2 (L : Inx := 0) is      -- Default value: assume mutable
         record
            S : String (1 .. L);
         end record;

      V1 : Rec1 (5);
      V2 : Rec2;
   begin
      for I in V1.S'Range loop         -- for_in_for_for_of
         X := V1.S (I);
         X := V1.S (I);
      end loop;
      for I in V2.S'Range loop
         X := V2.S (I);
      end loop;
   end;

   for I in Mat'Range (1) loop         -- OK, multidimensional array
      for J in Mat'Range (2) loop
         Mat (I, J) := False;
      end loop;
   end loop;

end Test_For_In_For_For_Of;
