----------------------------------------------------------------------
--  Rules.Object_Declarations - Package body                       --
--                                                                  --
--  This  software  is  (c)  CSEE  and Adalog  2004-2007.  The  Ada --
--  Controller  is  free software;  you can redistribute  it and/or --
--  modify  it under  terms of  the GNU  General Public  License as --
--  published by the Free Software Foundation; either version 2, or --
--  (at your  option) any later version.  This  unit is distributed --
--  in the hope  that it will be useful,  but WITHOUT ANY WARRANTY; --
--  without even the implied warranty of MERCHANTABILITY or FITNESS --
--  FOR A  PARTICULAR PURPOSE.  See the GNU  General Public License --
--  for more details.   You should have received a  copy of the GNU --
--  General Public License distributed  with this program; see file --
--  COPYING.   If not, write  to the  Free Software  Foundation, 59 --
--  Temple Place - Suite 330, Boston, MA 02111-1307, USA.           --
--                                                                  --
--  As  a special  exception, if  other files  instantiate generics --
--  from the units  of this program, or if you  link this unit with --
--  other files  to produce  an executable, this  unit does  not by --
--  itself cause the resulting executable  to be covered by the GNU --
--  General  Public  License.   This  exception  does  not  however --
--  invalidate any  other reasons why the executable  file might be --
--  covered by the GNU Public License.                              --
--                                                                  --
--  This  software is  distributed  in  the hope  that  it will  be --
--  useful,  but WITHOUT  ANY  WARRANTY; without  even the  implied --
--  warranty  of  MERCHANTABILITY   or  FITNESS  FOR  A  PARTICULAR --
--  PURPOSE.                                                        --
----------------------------------------------------------------------

-- ASIS
with
  Asis.Clauses,
  Asis.Declarations,
  Asis.Elements,
  Asis.Expressions;

-- Adalog
with
  A4G_Bugs,
  Thick_Queries,
  Utilities;

-- AdaControl
with
  Framework.Language,
  Framework.Scope_Manager;
pragma Elaborate (Framework.Language);

package body Rules.Object_Declarations is
   use Framework, Framework.Control_Manager;

   -- Algorithm
   --
   -- subrule Min_Integer_Span is fairly simple.
   --
   -- for subrule Volatile_No_Address, we avoid relying on Corresponding_Representation_Clauses
   -- and Corresponding_Pragmas, because they are not properly defined (since they take a
   -- declaration as parameter, it is not clear what happens if a declaration has several
   -- names, and the pragma or representation clause applies only to part of them).
   --
   -- We therefore use a Scoped_Store where every declared variable is added, and updated
   -- whenever we find a pragma volatile of address clause. At scope exit, we just need to
   -- browse the current level. Of course, it works because representation items must be
   -- declared in the same scope as the variable.

   type Subrules is (Min_Integer_Span, Volatile_No_Address, Address_Not_Volatile);
   subtype Vol_Addr_Rules is Subrules range Volatile_No_Address .. Address_Not_Volatile;
   package Subrules_Flag_Utilities is new Framework.Language.Flag_Utilities (Subrules);

   type Subrule_Set is array (Subrules) of Boolean;
   No_Rule : constant Subrule_Set := (others => False);
   Rule_Used : Subrule_Set := No_Rule;
   Save_Used : Subrule_Set;

   type Object_Kinds is (K_All, K_Variable, K_Constant);
   package Object_Kinds_Utilities is new Framework.Language.Modifier_Utilities (Object_Kinds, "K_");

   type Object_Context is new Basic_Rule_Context with
      record
         Min_Values : Thick_Queries.Biggest_Natural := 0;
      end record;
   Ctl_Contexts : array (Subrules, Object_Kinds, Control_Kinds) of Object_Context;
   Vno_Context  : array (Vol_Addr_Rules) of Basic_Rule_Context;

   -- Data for subrule Volatile_No_Address and Address_Not_Volatile:
   type Repr_Rec is
      record
         Variable : Asis.Defining_Name;
         Volatile : Boolean;
         Address  : Boolean;
      end record;
   procedure Clear (Rec : in out Repr_Rec) is   -- null
      pragma Unreferenced (Rec);
   begin
      null;
   end Clear;
   function Is_Equivalent (L, R : Repr_Rec) return Boolean is
      use Asis.Elements;
   begin
      return Is_Equal (L.Variable, R.Variable);
   end Is_Equivalent;
   package Repr_Store is new Framework.Scope_Manager.Scoped_Store (Repr_Rec, Is_Equivalent);

   ----------
   -- Help --
   ----------

   procedure Help is
      use Subrules_Flag_Utilities, Utilities;
   begin
      User_Message ("Rule: " & Rule_Id);
      User_Message ("Control allowed forms of object declarations");
      User_Message;
      Help_On_Flags ("Parameter(1):");
      User_Message ("Parameter(2..)");
      User_Message ("   for Min_Integer_Span: [all|constant|variable] <value>");
   end Help;

   -----------------
   -- Add_Control --
   -----------------

   procedure Add_Control (Ctl_Label : in Wide_String; Ctl_Kind : in Control_Kinds) is
      use Subrules_Flag_Utilities, Object_Kinds_Utilities, Thick_Queries, Framework.Language;
      Subrule : Subrules;
      Ok      : Object_Kinds;
      Vc      : Object_Context;
   begin
      if not Parameter_Exists then
         Parameter_Error (Rule_Id, "missing subrule name");
      end if;

      Subrule := Get_Flag_Parameter (Allow_Any => False);

      case Subrule is
         when Min_Integer_Span =>
            if not Parameter_Exists then
               Parameter_Error (Rule_Id, "missing number of allowed values");
            end if;
            loop
               Ok := Get_Modifier (Required => False);
               Vc := (Basic.New_Context (Ctl_Kind, Ctl_Label) with Get_Integer_Parameter (Min => 1));
               if Ok = K_All or Ok = K_Constant then
                  if Ctl_Contexts (Subrule, K_Constant, Ctl_Kind).Min_Values /= 0 then
                     Parameter_Error (Rule_Id, "subrule already given for constants");
                  end if;
                  Ctl_Contexts (Subrule, K_Constant, Ctl_Kind) := Vc;
               end if;
               if Ok = K_All or Ok = K_Variable then
                  if Ctl_Contexts (Subrule, K_Variable, Ctl_Kind).Min_Values /= 0 then
                     Parameter_Error (Rule_Id, "subrule already given for variables");
                  end if;
                  Ctl_Contexts (Subrule, K_Variable, Ctl_Kind) := Vc;
               end if;
               exit when not Parameter_Exists;
            end loop;
         when Volatile_No_Address
            | Address_Not_Volatile
            =>
            if Parameter_Exists then
               Parameter_Error (Rule_Id, "subrule has no parameters");
            end if;

            if Rule_Used (Subrule) then
               Parameter_Error (Rule_Id, "subrule already given");
            end if;

            Vno_Context (Subrule) := Basic.New_Context (Ctl_Kind, Ctl_Label);
      end case;
      Rule_Used (Subrule) := True;
   end Add_Control;

   -------------
   -- Command --
   -------------

   procedure Command (Action : Framework.Rules_Manager.Rule_Action) is
      use Framework.Rules_Manager;
   begin
      case Action is
         when Clear =>
            Rule_Used := No_Rule;
            for Sr in Subrules loop
               for Ok in Object_Kinds loop
                  for Rt in Control_Kinds loop
                     Ctl_Contexts (Sr, Ok, Rt).Min_Values := 0;
                  end loop;
               end loop;
            end loop;
         when Suspend =>
            Save_Used := Rule_Used;
            Rule_Used := No_Rule;
         when Resume =>
            Rule_Used := Save_Used;
      end case;
   end Command;


   -------------
   -- Prepare --
   -------------

   procedure Prepare is
   begin
      if not (Rule_Used (Volatile_No_Address) or Rule_Used (Address_Not_Volatile)) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Repr_Store.Activate;
   end Prepare;

   -------------------------
   -- Process_Declaration --
   -------------------------

   procedure Process_Declaration (Decl : in Asis.Declaration) is
      use Thick_Queries;
      use Asis, Asis.Declarations, Asis.Elements;

      function Decl_Type_Declaration return Asis.Declaration is
         -- returns the declaration of the type of Decl,
         -- nil_element for anonymous type declarations
         use Asis.Expressions;
         use Utilities;
         Def      : Asis.Definition;
         St_Name  : Asis.Expression;
      begin
         Def := Object_Declaration_View (Decl);
         if Definition_Kind (Def) /= A_Subtype_Indication then
            -- anonymous array, task, protected
            return Nil_Element;
         end if;
         St_Name := Subtype_Simple_Name (Def);
         if Expression_Kind (St_Name) = An_Attribute_Reference then
            case A4G_Bugs.Attribute_Kind (St_Name) is
               when A_Base_Attribute =>
                  -- for our purpose, the prefix will do as well
                  St_Name := Simple_Name (Prefix (St_Name));
               when A_Class_Attribute =>
                  -- Certainly not an integer type...
                  -- For volatile, we have no way of retrieving Corresponding_Pragmas
                  --   => give up
                  return Nil_Element;
               when others =>
                  Failure ("Bad attribute", St_Name);
            end case;
         end if;
         return A4G_Bugs.Corresponding_Name_Declaration (St_Name);
      end Decl_Type_Declaration;

      procedure Process_Min_Integer_Span is
         use Framework.Reports;

         Val      : Extended_Biggest_Natural;
         Type_Decl : Asis.Declaration;
         Type_Def : Asis.Definition;
         Obj_Kind : Object_Kinds;
      begin
         -- Check we have an object of an integer type
         Type_Decl := Decl_Type_Declaration;
         if Is_Nil (Type_Decl) then
            return;
         end if;
         Type_Def := Type_Declaration_View (Type_Decl);
         if Type_Kind (Type_Def) not in A_Signed_Integer_Type_Definition .. A_Modular_Type_Definition then
            return;
         end if;

         if Declaration_Kind (Decl) = A_Constant_Declaration then
            Obj_Kind := K_Constant;
         else
            Obj_Kind := K_Variable;
         end if;

         -- Check values

         declare
            Lengths : constant Extended_Biggest_Natural_List := Discrete_Constraining_Lengths (Decl);
         begin
            if Lengths'Length = 0 then
               -- The type is a 'base f.e. => treat like dynamic
               return;
            end if;
            Val := Lengths (1);
         end;

         if Val = Not_Static then
            return;
         end if;

         -- Note: Unspecified values of Range/Obj_Kind/Control contain 0, and Val is >= 0
         --       No problem in the following tests
         if Val < Ctl_Contexts (Min_Integer_Span, Obj_Kind, Check).Min_Values  then
            Report (Rule_Id,
                    Ctl_Contexts (Min_Integer_Span, Obj_Kind, Check),
                    Get_Location (Decl),
                    "integer object declaration has too few values ("
                    & Biggest_Int_Img (Val)
                    & ')');
         elsif Val < Ctl_Contexts (Min_Integer_Span, Obj_Kind, Search).Min_Values  then
            Report (Rule_Id,
                    Ctl_Contexts (Min_Integer_Span, Obj_Kind, Search),
                    Get_Location (Decl),
                    "integer object declaration has too few values ("
                    & Biggest_Int_Img (Val)
                    & ')');
         end if;

         if Val < Ctl_Contexts (Min_Integer_Span, Obj_Kind, Count).Min_Values  then
            Report (Rule_Id,
                    Ctl_Contexts (Min_Integer_Span, Obj_Kind, Count),
                    Get_Location (Decl),
                    "");
         end if;
      end Process_Min_Integer_Span;

      procedure Process_Volatile_Address is
         Decl_Names : constant Asis.Defining_Name_List := Names (Decl);
         Type_Decl  : constant Asis.Declaration := Decl_Type_Declaration;
         Volatile_T : Boolean := False;
      begin
         if not Is_Nil (Type_Decl) then
            declare
               Pragmas : constant Asis.Pragma_Element_List := Corresponding_Pragmas (Type_Decl);
            begin
               for P in Pragmas'Range loop
                  if Pragma_Kind (Pragmas (P)) = A_Volatile_Pragma then
                     Volatile_T := True;
                     exit;
                  end if;
               end loop;
            end;
         end  if;

         for N in Decl_Names'Range loop
            Repr_Store.Push ((Decl_Names (N), Volatile => Volatile_T, Address => False));
         end loop;
      end Process_Volatile_Address;

   begin  -- Process_Declaration
      if Rule_Used = No_Rule then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if Rule_Used (Min_Integer_Span) then
         Process_Min_Integer_Span;
      end if;

      if (Rule_Used (Volatile_No_Address) or Rule_Used (Address_Not_Volatile))
        and then Declaration_Kind (Decl) = A_Variable_Declaration
      then
         Process_Volatile_Address;
      end if;
   end Process_Declaration;

   --------------------
   -- Process_Pragma --
   --------------------

   procedure Process_Pragma (Prgma : in Asis.Pragma_Element) is
      use Asis, Asis.Elements, Asis.Expressions;
      use Framework.Reports, Framework.Scope_Manager, Utilities;

      Name      : Asis.Expression;
      Repr_Data : Repr_Rec;
   begin
      if not (Rule_Used (Volatile_No_Address) or Rule_Used (Address_Not_Volatile)) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if Pragma_Kind (Prgma) /= A_Volatile_Pragma then
         return;
      end if;
      Name := Actual_Parameter (Pragma_Argument_Associations (Prgma) (1));
      if Expression_Kind (Name) = An_Attribute_Reference then
         -- A variable cannot be an attribute
         -- pragma volatile is not allowed on T'Base
         -- therefore, it can only be T'Class
         Uncheckable (Rule_Id,
                      False_Negative,
                      Get_Location (Name),
                      "cannot check variables of class-wide type");
         return;
      end if;

      if Declaration_Kind (A4G_Bugs.Corresponding_Name_Declaration (Name)) /= A_Variable_Declaration then
         return;
      end if;

      -- Here, we have a pragma volatile on a variable
      Repr_Data := (Corresponding_Name_Definition (Name), Volatile => True, Address => False);
      Repr_Store.Reset (Repr_Data, Current_Scope_Only);
      Assert (Repr_Store.Data_Available, "missing declaration"); -- Pragma must be in same scope as declaration

      Repr_Data := Repr_Store.Current_Data;
      Repr_Data.Volatile := True;
      Repr_Store.Update_Current (Repr_Data);
   end Process_Pragma;

   -----------------------------------
   -- Process_Representation_Clause --
   -----------------------------------

   procedure Process_Representation_Clause (Clause : in Asis.Representation_Clause) is
      use Asis, Asis.Clauses, Asis.Elements, Asis.Expressions;
      use Framework.Scope_Manager, Thick_Queries, Utilities;

      Name      : Asis.Expression;
      Repr_Data : Repr_Rec;
   begin
      if not (Rule_Used (Volatile_No_Address) or Rule_Used (Address_Not_Volatile)) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      case Representation_Clause_Kind (Clause) is
         when An_Attribute_Definition_Clause =>
            Name := Representation_Clause_Name (Clause);
            if A4G_Bugs.Attribute_Kind (Name) /= An_Address_Attribute then
               return;
            end if;
            Name := Simple_Name (Prefix (Name));
         when An_At_Clause =>
            Name := Representation_Clause_Name (Clause);
         when others =>
            return;
      end case;
      if Declaration_Kind (A4G_Bugs.Corresponding_Name_Declaration (Name)) /= A_Variable_Declaration then
         return;
      end if;

      -- Here, we have an address repr_clause on a variable
      Repr_Data := (Corresponding_Name_Definition (Name), Volatile => False, Address => True);
      Repr_Store.Reset (Repr_Data, Current_Scope_Only);
      Assert (Repr_Store.Data_Available, "missing declaration"); -- Pragma must be in same scope as declaration

      Repr_Data         := Repr_Store.Current_Data;
      Repr_Data.Address := True;
      Repr_Store.Update_Current (Repr_Data);
   end Process_Representation_Clause;


   ------------------------
   -- Process_Scope_Exit --
   ------------------------

   procedure Process_Scope_Exit is
      use Framework.Reports, Framework.Scope_Manager;

      Repr_Data : Repr_Rec;
   begin
      if not (Rule_Used (Volatile_No_Address) or Rule_Used (Address_Not_Volatile)) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Repr_Store.Reset (Current_Scope_Only);
      while Repr_Store.Data_Available loop
         Repr_Data := Repr_Store.Current_Data;
         if Rule_Used (Volatile_No_Address) and Repr_Data.Volatile and not Repr_Data.Address then
            Report (Rule_Id,
                    Vno_Context (Volatile_No_Address),
                    Get_Location (Repr_Data.Variable),
                    "variable is volatile and has no address clause");
         end if;
         if Rule_Used (Address_Not_Volatile) and Repr_Data.Address and not Repr_Data.Volatile then
            Report (Rule_Id,
                    Vno_Context (Address_Not_Volatile),
                    Get_Location (Repr_Data.Variable),
                    "variable has address clause and is not volatile");
         end if;
         Repr_Store.Next;
      end loop;
   end Process_Scope_Exit;

begin  -- Rules.Object_Declarations
   Framework.Rules_Manager.Register (Rule_Id,
                                     Rules_Manager.Semantic,
                                     Help_CB        => Help'Access,
                                     Add_Control_CB => Add_Control'Access,
                                     Command_CB     => Command'Access,
                                     Prepare_CB     => Prepare'Access);
end Rules.Object_Declarations;
