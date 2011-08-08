with Ada.Numerics.Generic_Elementary_Functions;
with X_Declarations.Child;
with X_Declarations_Locations;
procedure T_declarations is       -- library_procedure
   procedure Test_Anonymous_Subtype is separate;   -- separate

   type I1 is range 1 .. 10;      -- signed_type, integer_type
   type I2 is mod 128;            -- binary_modular_type, modular_type, integer_type
   type I3 is mod 127;            -- non_binary_modular_type, modular_type, integer_type

   type Fl is digits 5;                    -- float_type
   type Fx1 is delta 0.1 range 0.0 .. 1.0; -- ordirnary_fixed_type_no_small, ordinary_fixed_type, fixed_type
   type Fx2 is delta 0.1 digits 5;         -- decimal_fixed_type, fixed_type

   type Enum is (A, B, 'c', D, 'e');       -- enumeration_type, character_literal x2

   task T1 is                     -- single_task, task
     entry E (I : Integer := 1);  -- task_entry, defaulted_parameter
   end T1;
   task body T1 is
      procedure P is              -- task_body procedure, nested procedure, local procedure
      begin
         null;                    -- null_procedure
      end;
   begin
      null;
   exception                      -- handlers
      when others =>
         null;
   end T1;

   task type T2 (X : Integer) is  -- task_type, task, discriminant
     entry E;                     -- task_entry
   end T2;
   task body T2 is
   begin
      null;
   end T2;

   protected P1 is                                     -- single_protected, protected
      entry E1 (I : out Integer; J : in out Integer);  -- protected_entry, out_parameter, in_out_parameter
      entry E2;                                        -- protected_entry, multiple_protected_entries
   end P1;
   protected body P1 is
      entry E1 (I : out Integer; J : in out Integer) when True  is --out_parameter, in_out_parameter
      begin
         null;
      end E1;
      entry E2 when True is
      begin
         null;
      end E2;
   end P1;

   protected type P2 (X : Integer := 0) is  -- protected_type, protected, defaulted_discriminant, discriminant
      entry E1;                             -- protected_entry
      entry E2;                             -- protected_entry, multiple_protected_entries
   private
      I : Integer;                          -- uninitialized_protected_field
      J : Integer := 0;                     -- initialized_protected_field
   end P2;
   protected body P2 is
      entry E1 when True is
      begin
         null;
      end E1;
      entry E2 when True is
      begin
         null;
      end E2;
   end P2;

   E : exception;         -- exception
   NN1 : constant := 1;   -- named_number
   NN2 : constant := 1.0; -- named_number

   type Acc1;                      -- incomplete_type
   type Acc1 is access Integer;    -- access_type
   type Acc2 is access procedure;  -- access_subprogram_type, access_type
   type Acc3 is access T2;         -- access_task_type, access_type
   type Acc4 is access P2;         -- access_protected_type, access_type

   type Der_Task is new T2;        -- derived_type
   type Acc5 is access Der_Task;   -- access_task_type, access_type

   type Acc6 is access all Integer;      -- access_type, access_all_type
   type Acc7 is access constant Integer; -- access_type, access_constant_type

   I,J,K : aliased Integer;               -- variable, aliased, uninitialized_variable, multiple_names
   C : aliased constant Character := ' '; -- constant, aliased

   type Rec1 is tagged null record;                       -- null_tagged_type, tagged_type, record_type
   type Rec2 (X : Integer) is tagged limited null record; -- null_tagged_type, tagged_type, record_type, discriminant
   type Rec3 is null record;                              -- null_ordinary_record_type, ordinary_record_type, record_type
   type Rec4 (X : Integer := 0) is                        -- ordinary_record_type, record_type, defaulted_discriminant, discriminant
      record
         case X is               -- variant_part
            when 0 =>
               I : Integer;      -- uninitialized_record_field
            when others =>
               J : Integer := 0; -- initialized_record_field
         end case;
      end record;
   type Rec5 is null record;  -- null_ordinary_record_type, ordinary_record_type, record_type
   type Rec6 is record        -- null_ordinary_record_type, ordinary_record_type, record_type
      null;
   end record;
   type Rec7 is            -- ordinary_record_type, record_type
      record
         I : Integer;      -- uninitialized_record_field
         J : Integer := 0; -- initialized_record_field
      end record;
   Vclass : Rec1'Class          := Rec1'(null record);        -- variable, class_wide_variable
   Cclass : constant Rec1'Class := Rec1'(null record);        -- constant, class_wide_constant

   type Arr1 is array (1 .. 10) of Character;                 -- constrained_array_type, array, anonymous_subtype_declaration
   type Arr2 is array (Positive range <>) of Integer;         -- unconstrained_array_type, array
   subtype Subarr21 is Arr2;                                  -- subtype, unconstrained_subtype
   subtype Subarr22 is Arr2 (1 .. 3);                         -- subtype, anonymous_subtype_declaration
   subtype Subarr23 is Subarr22;                              -- subtype, unconstrained_subtype
   VArr1 : array (1 .. 10) of Character;                      -- anonymous_subtype_declaration, variable, single_array, constrained_array_variable, array, uninitialized_variable
   Varr2 : Arr2 := (1, 2, 3);                                 -- variable, unconstrained_array_variable, array
   Varr3 : array (Positive range <>) of Integer := (1, 2, 3); -- variable, single_array, unconstrained_array_variable, array
   Varr4 : Subarr21 := (1,2, 3);                              -- variable, unconstrained_array_variable, array
   Varr5 : Subarr23;                                          -- variable, constrained_array_variable, array, uninitialized_variable

   type Der1 is new Rec1 with null record;                   -- null_extension, extension, tagged_type, record_type
   type Der2 (Y : Integer) is new Rec1 with null record;     -- null_extension, extension, tagged_type, record_type, discriminant
   type Der3 (Y : Integer) is new Rec2 (Y) with null record; -- null_extension, extension, tagged_type, record_type, discriminant, anonymous_subtype_declaration
   type Der4 is new Rec3;                                    -- derived_type

   type T_Float is digits 5;                                 -- float_type
   type T_Fixed1 is delta 0.01 range 0.0 .. 1.0;             -- ordinary_fixed_type_with_small, ordinary_fixed_type, fixed_type
   for T_Fixed1'Small use 0.01;
   type T_Fixed2 is delta 0.01 digits 7;                     -- decimal_fixed_type, fixed_type

   generic                                                          -- Nested_Generic_Procedure, generic
      I : Integer := 1;                                             -- defaulted_generic_parameter
   procedure P (J : Integer := 1; K : in out Float; L : out Float); -- Defaulted_Parameter, In_Out_Parameter, Out_Parameter
   procedure P (J : Integer := 1; K : in out Float; L : out Float) is begin null; end; -- null_procedure

   package Pack1 is private end Pack1;              -- nested_package, empty_visible_part, empty_private_part
   package body Pack1 is
   end Pack1;

   package Pack2 is                                 -- nested_package
      type Priv1 is private;                        -- Non_Limited_Private_Type
      type Priv2 is limited private;                -- Limited_Private_Type
      type Ext1 is new Rec1 with private;           -- Private_Extension
      type Abs1 is abstract tagged private;         -- Non_Limited_Private_Type, Abstract_Type
      type Abs2 is abstract tagged limited private; -- Non_Limited_Private_Type, Abstract_Type
      procedure P (X : Abs1) is abstract;           -- Public Procedure, Nested Procedure, Local Procedure, Abstract_Procedure
      function  F (Y : Abs2) return Integer is abstract; -- Abstract_Function
      Deferred : constant Priv1;                    -- Constant, Deferred_Constant
   private
      type Priv1 is new Integer;                    -- Derived_Type
      type Priv2 is new Integer;                    -- Derived_Type
      type Ext1 is new Rec1 with null record;       -- Null_Extension, Extension, Tagged_Type, Record_Type
      type Abs1 is abstract tagged null record;     -- Null_Tagged_Type, Tagged_Type, Record_Type, Abstract_Type
      type Abs2 is abstract tagged limited          -- Tagged_Type, Record_Type, Abstract_Type
         record
            X : Integer;                            -- Uninitialized_Record_Field
         end record;
      procedure Proc1;                              -- Private Procedure, Nested Procedure, Local Procedure
      Deferred : constant Priv1 := 0;
   end Pack2;
   package body Pack2 is
      type Abs3 is abstract new Abs2 with null record;   -- Null_Extension, Extension, Tagged_Type, Record_Type, Abstract_Type
      procedure Proc1 is
      begin
         null;                                           -- Null_Procedure
      end Proc1;
      procedure Proc2 is                                 -- Own procedure, nested procedure, local procedure
      begin
         declare
            procedure Proc3 is                           -- Nested Procedure, Local Procedure, Block Procedure
            begin
               null;                                     -- Null Procedure
            end Proc3;
         begin
            null;
         end;
      end Proc2;
   begin                                                 -- package_statements
      null;
   end Pack2;

   package Pack3 renames Pack2;                          -- not_operator_renaming, non_identical_renaming, renaming
   generic package Generic_Elementary_Functions          -- Not_Operator_Renaming, renaming
      renames Ada.Numerics.Generic_Elementary_Functions;

   function "+" (X, Y : Integer) return Integer is       -- operator, predefined_operator, multiple_names
   begin
      return 1;
   end "+";

   function "-" (X, Y : Integer) return Integer;         -- Operator, Predefined_operator, multiple_names
   function "-" (X, Y : Integer) return Integer is       -- Multiple_names
   begin
      return 1;
   end "-";

   function F1  (X, Y : Integer) return Integer renames "+";            -- renaming, operator_renaming, non_identical_operator_renaming, non_identical_renaming, multiple_names
   function F2  (X, Y : Integer) return Integer renames Standard."+";   -- renaming, operator_renaming, non_identical_operator_renaming, non_identical_renaming, multiple_names
   function "*" (X, Y : Integer) return Integer renames Standard."*";   -- renaming, operator_renaming, multiple_names

   generic                                                                    -- Nested_Generic_Package, generic
      Global : in out Integer;                                                -- in_out_generic_parameter
      type T is private;                                                      -- formal type
      with procedure Formal_P;                                                -- formal_procedure
      with function Formal_F return Integer;                                  -- formal_function
      with package EF is new Ada.Numerics.Generic_Elementary_Functions (<>);  -- formal_package
   package Test_Formals is private end;                                       -- empty_visible_part, empty_private_part
   package body Test_Formals is
   begin
      null;                                                                   -- package statements
   end Test_Formals;

   subtype Int1 is Integer range 1..10;                                 -- subtype
   subtype Int2 is Integer;                                             -- subtype, unconstrained_subtype

   Arr : Integer renames X_Declarations.Arr (1);                        -- not_operator_renaming, non_identical_renaming, renaming
   function Succ (X : Integer) return Integer renames Integer'Succ;     -- renaming, not_operator_renaming, non_identical_renaming
   function "/" (X, Y : Integer) return Integer renames Standard."+";   -- renaming, operator_renaming, non_identical_operator_renaming, non_identical_renaming, multiple_names

   procedure Predefined_Operator is separate;                           -- separate

   Renf1 : Integer renames Succ (1);                                    -- renaming, not_operator_renaming, non_identical_renaming, function_call_renaming
   Renf2 : Integer renames "+"(1,2);                                    -- renaming, not_operator_renaming, non_identical_renaming, function_call_renaming
begin
   null;                                                                -- null_procedure
end T_declarations;
