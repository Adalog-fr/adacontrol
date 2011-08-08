----------------------------------------------------------------------
--  Rules.Reduceable_Scope - Package body                           --
--                                                                  --
--  This software  is (c) The European Organisation  for the Safety --
--  of Air  Navigation (EUROCONTROL) and Adalog  2004-2005. The Ada --
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

-- Ada
with
  Ada.Unchecked_Deallocation,
  Ada.Strings.Wide_Unbounded;


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
  Framework.Queries,
  Framework.Scope_Manager,
  Framework.Symbol_Table;
pragma Elaborate (Framework.Language);

package body Rules.Reduceable_Scope is
   use Framework, Framework.Control_Manager, Framework.Scope_Manager, Utilities;
   use Ada.Strings.Wide_Unbounded;

   -- Algorithm:
   --
   -- To check declarations that can be moved to an inner scope:
   -- We use a Scoped_Store to maintain a list of declared entities.
   -- Each entry consists of the defining name of the entity, plus a path to where
   -- the declaration could be moved. This path is the list of scopes between the scope
   -- of the declaration (not included) and the scope of a reference to the entity (included).
   --
   -- When a reference is encountered, the corresponding path is compared to the one
   -- stored with the entity. If they are unequal, only the common part of both paths
   -- is kept. If there is no such common part, the entity cannot be moved and is removed
   -- from the store.
   --
   -- At scope exit, remainining entities can be moved, and the top of the associated path
   -- tells where. If there is no path at all, the entity has not been referenced.
   --
   -- To check movable use clauses:
   -- We use a separate Scoped_Store, since a "use" of a use clause is when it's name
   -- does *not* appear...
   --
   -- To check declarations that can be moved from package spec to body:
   -- We just use a symbol table, where we keep elements and where they were used from.
   -- Reports are issued when leaving the corresponding visibility scope.
   --
   -- Note on memory management of paths:
   -- Paths that are no more needed are freed by the scope manager from the associated Clear
   -- procedures; they should not be freed from any other place.

   type Declaration_Check_Kinds is (Check_Not_Checkable,
                                    Check_All,
                                    Check_Variable, Check_Constant,  Check_Subprogram, Check_Type,
                                    Check_Package,  Check_Exception, Check_Generic,    Check_Use);
   subtype Subrules is Declaration_Check_Kinds range Check_All .. Declaration_Check_Kinds'Last;
   package Subrules_Flag_Utilities is new Framework.Language.Flag_Utilities (Subrules, Prefix => "CHECK_");
   subtype Check_Kind is Subrules range Subrules'Succ (Check_All) .. Subrules'Last;

   type Check_Kind_Set is array (Check_Kind) of Boolean;
   No_Check : constant Check_Kind_Set := (others => False);

   type Restriction_Kinds is (No_Blocks, To_Body);
   package Restriction_Utilities is new Framework.Language.Modifier_Utilities (Restriction_Kinds);

   Rule_Used        : Check_Kind_Set := (others => False);
   Save_Used        : Check_Kind_Set;
   Ctl_Contexts     : array (Check_Kind) of Basic_Rule_Context;
   Ctl_Restrictions : array (Check_Kind) of Restriction_Utilities.Modifier_Set
                                            := (others => Restriction_Utilities.Empty_Set);

   -- Management of declaration information, non package visible items
   type Scope_List_Access is access Scope_List;
   procedure Free is new Ada.Unchecked_Deallocation (Scope_List, Scope_List_Access);

   type Declaration_Info is
      record
         Elem  : Asis.Element;
         Kind  : Check_Kind;
         Path  : Scope_List_Access;
      end record;
   function Equivalent_Keys (L, R : Declaration_Info) return Boolean;
   procedure Clear (Item : in out Declaration_Info);
   package Local_Declarations is new Scoped_Store (Declaration_Info, Equivalent_Keys);

   -- Management of declaration information, package visible items
   type Package_Usage is (Not_Used, Body_Used, Outside_Used);
   type Package_Info is
      record
         Usage : Package_Usage;
         Kind  : Check_Kind;
      end record;
   package Package_Visibles is new Framework.Symbol_Table.Data_Access (Package_Info);

   -- Management of declaration information, use clauses
   type Use_Info is
      record
         Elem  : Asis.Element;
         Path  : Scope_List_Access;
         Image : Unbounded_Wide_String;
      end record;
   function Equivalent_Keys (L, R : Use_Info) return Boolean;
   procedure Clear (Item : in out Use_Info);
   package Use_Clauses is new Scoped_Store (Use_Info, Equivalent_Keys);


   ----------
   -- Help --
   ----------

   procedure Help is
      use Subrules_Flag_Utilities, Restriction_Utilities;
   begin
      User_Message  ("Rule: " & Rule_Id);
      Help_On_Flags (Header => "Parameter(s): {<restriction>}", Footer => "(optional)");
      Help_On_Modifiers (Header => "<restriction>:");
      User_Message  ("Control declarations that could be moved to an inner scope,");
      User_Message  ("I.e. where all references are from a single nested scope");
   end Help;

   -----------------
   -- Add_Control --
   -----------------

   procedure Add_Control (Ctl_Label : in Wide_String; Ctl_Kind : in Control_Kinds) is
      use Framework.Language, Subrules_Flag_Utilities, Restriction_Utilities;
      Restrictions : Modifier_Set;
      Subrule : Subrules;
   begin
      if Parameter_Exists then
         Restrictions := Get_Modifier_Set;
         Subrule      := Get_Flag_Parameter (Allow_Any => False);
      else
         Restrictions := Empty_Set;
         Subrule      := Check_All;
      end if;

      loop
         if Subrule = Check_All then
            if Rule_Used /= No_Check then
               Parameter_Error (Rule_Id, "Rule already specified");
            end if;
            Rule_Used        := (others => True);
            Ctl_Contexts     := (others => Basic.New_Context (Ctl_Kind, Ctl_Label));
            Ctl_Restrictions := (others => Restrictions);
         else
            if Rule_Used (Subrule) then
               Parameter_Error (Rule_Id, "Rule already specified for this parameter");
            end if;
            Rule_Used        (Subrule) := True;
            Ctl_Contexts     (Subrule) := Basic.New_Context (Ctl_Kind, Ctl_Label);
            Ctl_Restrictions (Subrule) := Restrictions;
         end if;
         exit when not Parameter_Exists;
         Restrictions := Get_Modifier_Set;
         Subrule      := Get_Flag_Parameter (Allow_Any => False);
      end loop;
   end Add_Control;


   -------------
   -- Command --
   -------------

   procedure Command (Action : Framework.Rules_Manager.Rule_Action) is
      use Framework.Rules_Manager;
   begin
      case Action is
         when Clear =>
            Rule_Used  := No_Check;
         when Suspend =>
            Save_Used := Rule_Used;
            Rule_Used := No_Check;
         when Resume =>
            Rule_Used := Save_Used;
      end case;
   end Command;


   -------------
   -- Prepare --
   -------------

   procedure Prepare is
   begin
      if Rule_Used /= No_Check then
         Local_Declarations.Activate;
         Use_Clauses.Activate;
      end if;
   end Prepare;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Declaration_Info) is
   begin
      Free (Item.Path);
   end Clear;

   -----------
   -- Clear --
   -----------

   procedure Clear (Item : in out Use_Info) is
   begin
      Free (Item.Path);
   end Clear;

   ---------------------
   -- Equivalent_Keys --
   ---------------------

   function Equivalent_Keys (L, R : Declaration_Info) return Boolean is
      use Asis.Elements;
   begin
      return Is_Equal (L.Elem, R.Elem);
   end Equivalent_Keys;

   function Equivalent_Keys (L, R : Use_Info) return Boolean is
      use Asis.Elements;
   begin
      return Is_Equal (L.Elem, R.Elem);
   end Equivalent_Keys;

   ----------------------------
   -- Declaration_Check_Kind --
   ----------------------------

   function Declaration_Check_Kind (Decl : Asis.Declaration) return Declaration_Check_Kinds is
      use Asis, Asis.Declarations, Asis.Elements;
      use Thick_Queries;

      Temp : Asis.Element;
   begin
      case Element_Kind (Decl) is
         when A_Declaration =>
            case Declaration_Kind (Decl) is
               when Not_A_Declaration =>
                  Failure ("Not a declaration");

               when A_Component_Declaration         -------------- Nothing applicable
                  | A_Discriminant_Specification
                  | A_Choice_Parameter_Specification
                  | A_Parameter_Specification
                  | A_Formal_Declaration
                  | A_Loop_Parameter_Specification
                  | A_Single_Task_Declaration
                  | An_Entry_Declaration
                  | An_Entry_Index_Specification
                    =>
                  -- Things that cannot be moved:
                  --   Components of structured data
                  --   Identifiers of exception handlers
                  --   (generic) formal parameters
                  --   Control variables of for loops
                  --   Task objects (since it would change the master)
                  --   Entries
                  return Check_Not_Checkable;
               when A_Package_Body_Declaration
                  | A_Task_Body_Declaration
                  | A_Protected_Body_Declaration
                  | An_Entry_Body_Declaration
                  | A_Package_Body_Stub
                  | A_Task_Body_Stub
                  | A_Protected_Body_Stub
                    =>
                  -- These things always have an explicit spec => no need to consider
                  -- the name from the body
                  return Check_Not_Checkable;
               when An_Incomplete_Type_Declaration   -------------- Types
                  | A_Private_Type_Declaration
                  | A_Private_Extension_Declaration
                  | A_Subtype_Declaration
                    =>
                  return Check_Type;
               when An_Ordinary_Type_Declaration
                  | A_Task_Type_Declaration
                  | A_Protected_Type_Declaration
                    =>
                  -- Do not consider the declaration if it is a completion
                  -- since in this case, we use the defining name from the completed declaration.
                  if Is_Nil (Corresponding_Type_Declaration (Decl)) then
                     return Check_Type;
                  else
                     return Check_Not_Checkable;
                  end if;
               when A_Constant_Declaration  ------------------- Objects
                  | A_Deferred_Constant_Declaration
                  | An_Integer_Number_Declaration
                  | A_Real_Number_Declaration
                  | An_Enumeration_Literal_Specification
                    =>
                  return Check_Constant;
               when A_Variable_Declaration =>
                  Temp := Object_Declaration_View (Decl);
                  if Definition_Kind (Temp) = A_Subtype_Indication then
                     Temp := Subtype_Simple_Name (Temp);
                     if Expression_Kind (Temp) /= An_Attribute_Reference then
                        -- 'Base is not applicable to a task type, nor 'Class (for the moment!)
                        if Is_Type_Declaration_Kind (A4G_Bugs.Corresponding_Name_Declaration (Temp),
                                                     A_Task_Type_Declaration)
                        then
                           return Check_Not_Checkable;
                        end if;
                     end if;
                  end if;

                  return Check_Variable;
               when An_Object_Renaming_Declaration =>
                  -- Treat as variable even if it is a renaming of a constant
                  return Check_Variable;
               when A_Single_Protected_Declaration =>
                  return Check_Variable;
               when A_Procedure_Declaration  ------------ Subprograms
                  | A_Function_Declaration
                  | A_Procedure_Instantiation
                  | A_Function_Instantiation
                    =>
                  -- Dispatching operations are never movable, since they can be called without
                  -- their name appearing in the program text
                  if Is_Dispatching_Operation (Decl) then
                     return Check_Not_Checkable;
                  else
                     return Check_Subprogram;
                  end if;
               when A_Procedure_Body_Declaration
                  | A_Function_Body_Declaration
                  | A_Procedure_Body_Stub
                  | A_Function_Body_Stub
                    =>
                  -- Do not consider the body if there is an explicit spec.
                  -- since in this case, we use the defining name from the spec.
                  if Is_Nil (Corresponding_Declaration (Decl)) then
                     return Check_Subprogram;
                  else
                     return Check_Not_Checkable;
                  end if;
               when A_Procedure_Renaming_Declaration
                  | A_Function_Renaming_Declaration
                    =>
                  -- Renamings can be both completions and dispatching operations
                  -- (see comments above)
                  if Is_Dispatching_Operation (Decl) then
                     return check_not_checkable;
                  elsif Is_Nil (Corresponding_Declaration (Decl)) then
                     return Check_Subprogram;
                  else
                     return Check_Not_Checkable;
                  end if;
               when A_Package_Declaration   ---------------- Packages
                  | A_Package_Renaming_Declaration
                  | A_Package_Instantiation
                    =>
                  return Check_Package;
               when An_Exception_Declaration   ---------------- Exceptions
                  | An_Exception_Renaming_Declaration
                    =>
                  return Check_Exception;
               when A_Generic_Procedure_Declaration  -------------- Generics
                  | A_Generic_Function_Declaration
                  | A_Generic_Package_Declaration
                  | A_Generic_Package_Renaming_Declaration
                  | A_Generic_Procedure_Renaming_Declaration
                  | A_Generic_Function_Renaming_Declaration
                    =>
                  return Check_Generic;
               when others =>  ---------- Ada 2005 stuff only
                  return Check_Not_Checkable;
            end case;

         when A_Statement =>
            -- ASIS says:
            -- Statements result from references to statement labels, loop identifiers,
            -- and block identifiers.
            -- None of these are moveable
            return Check_Not_Checkable;

         when others =>
            Failure ("Unexpected place for defining name", Decl);
      end case;
   end Declaration_Check_Kind;

   ------------------------------
   -- Report_All_Package_Names --
   ------------------------------

   procedure Report_One_Name (Entity : Asis.Defining_Name; Info : in out Package_Info) is
      use Asis.Declarations;
      use Framework.Reports;
   begin
      case Info.Usage is
         when Not_Used =>
            if not Ctl_Restrictions (Info.Kind) (To_Body) then
               Report (Rule_Id,
                       Ctl_Contexts (Info.Kind),
                       Get_Location (Entity),
                       Defining_Name_Image (Entity) & " is not used");
            end if;
         when Body_Used =>
            Report (Rule_Id,
                    Ctl_Contexts (Info.Kind),
                    Get_Location (Entity),
                    "Declaration of "
                    & Defining_Name_Image (Entity)
                    & " can be moved into package body");
         when Outside_Used =>
            null;
      end case;
   end Report_One_Name;

   procedure Report_All_Package_Names is new Package_Visibles.On_Every_Entity_From_Scope (Report_One_Name);

   ---------------------------
   -- Process_Defining_Name --
   ---------------------------

   procedure Process_Defining_Name (Def: in Asis.Defining_Name) is
      use Asis, Asis.Declarations, Asis.Elements;

      Enclosing_Unit : Asis.Declaration;
      Enclosing_Decl : Asis.Declaration;
      Kind           : Declaration_Check_Kinds;
   begin
      if Rule_Used = No_Check then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Enclosing_Decl  := Enclosing_Element (Def);
      -- Make sure we have really the declaration
      -- (case of defining expanded names of child units)
      while Defining_Name_Kind (Enclosing_Decl) = A_Defining_Expanded_Name loop
         Enclosing_Decl := Enclosing_Element (Enclosing_Decl);
      end loop;

      if Is_Nil (Enclosing_Element (Enclosing_Decl)) then
         -- This is the defining name of a compilation unit
         return;
      end if;

      Kind := Declaration_Check_Kind (Enclosing_Decl);
      if Kind = Check_Not_Checkable or else not Rule_Used (Kind) then
         return;
      end if;

      Enclosing_Unit := Enclosing_Element (Enclosing_Decl);
      if Element_Kind (Enclosing_Unit) = A_Definition then
         Enclosing_Unit := Enclosing_Element (Enclosing_Unit);
      end if;
      case Declaration_Kind (Enclosing_Unit) is
         when A_Generic_Package_Declaration
           | A_Task_Type_Declaration
           | A_Single_Task_Declaration
           | A_Protected_Type_Declaration
           | A_Single_Protected_Declaration
           =>
            -- Never process declarations from generic packages, task specs and protected specs
            null;

         when A_Package_Declaration =>
            if not Package_Visibles.Is_Present (Def) then
               Package_Visibles.Store (Def, (Not_Used, Kind));
            end if;

         when others =>
            -- Consider that initialization is a reference from same scope
            case Kind is
               when Check_Constant =>
                  -- always initialized
                  return;
               when Check_Variable =>
                  case Declaration_Kind (Enclosing_Decl) is
                     when An_Object_Renaming_Declaration
                        | A_Single_Protected_Declaration
                          =>
                        -- Never initialized
                        null;
                     when others =>
                        if not Is_Nil (Initialization_Expression (Enclosing_Decl)) then
                           return;
                        end if;
                  end case;
               when others =>
                  null;
            end case;

            if Is_Equal (Enclosing_Decl, Current_Scope) then
               -- This is the defining name for the current scope
               -- => it belongs to the enclosing scope
               Local_Declarations.Push_Enclosing ((Elem  => Def,
                                                   Kind  => Kind,
                                                   Path  => null));
            else
               Local_Declarations.Push ((Elem  => Def,
                                         Kind  => Kind,
                                         Path  => null));
            end if;
      end case;
   end Process_Defining_Name;


   ------------------------
   -- Process_Identifier --
   ------------------------

   procedure Process_Identifier (Name : in Asis.Name) is
      use Asis, Asis.Elements;

      type Merge_Action is (Keep, Update, Delete);
      procedure Merge (Declaration_Path : in out Scope_List_Access;
                       Usage_Path       : in     Scope_List;
                       Blocks_Forbidden : in     Boolean;
                       Action           : out    Merge_Action)
      is
         -- Assert: Declaration_Path'First = Usage_Path'First, since they both correspond
         --         to the level (+1) where the same element is declared.
         -- Merge does /not/ free paths. This will be done by a call to Clear for the
         -- node of the scoped_store that contains the path.
         Top : Scope_Range := Usage_Path'Last;
      begin
         if Usage_Path'Length = 0 then
            -- Reference from same level as declaration
            -- This declaration cannot be moved. Remove it.
            Action := Delete;
            return;
         end if;

         -- Determine the common part of both paths
         if Declaration_Path /= null then
            -- Declaration_Path is null on the first reference
            if not Is_Equal (Usage_Path (Usage_Path'First), Declaration_Path (Declaration_Path'First)) then
               -- Nothing in common, declaration cannot be moved. Remove it.
               Action := Delete;
               return;
            end if;

            for I in Scope_Range range Usage_Path'First + 1 .. Usage_Path'Last loop
               if I > Declaration_Path'Last then
                  -- Declaration_Path is shorter and matches the beginning of Current_Path
                  -- => keep it
                  Action := Keep;
                  return;
               end if;

               if not Is_Equal (Usage_Path (I), Declaration_Path (I)) then
                  -- Keep in Declaration_Path the common part only
                  Top := I-1;
                  exit;
               end if;
            end loop;
         end if;

         -- Get rid of top scopes where nothing can be moved to
         while     Statement_Kind   (Usage_Path (Top)) = A_For_Loop_Statement
           or else Statement_Kind   (Usage_Path (Top)) = An_Accept_Statement
           or else (Statement_Kind  (Usage_Path (Top)) = A_Block_Statement and Blocks_Forbidden)
           or else Element_Kind     (Usage_Path (Top)) = An_Exception_Handler
           or else Declaration_Kind (Usage_Path (Top)) in A_Generic_Instantiation
         loop
            if Top = Usage_Path'First then
               -- Nothing left => remove declaration
               Action := Delete;
               return;
            end if;
            Top := Top - 1;
         end loop;

         Declaration_Path := new Scope_List'(Usage_Path (Usage_Path'First .. Top));
         Action           := Update;
      end Merge;

      Enclosing_Decl : Asis.Declaration;

      procedure Check_Body_Movable_Declaration is
         -- Pre: Enclosing_Decl is the package declaration that contains the declaration
         --      of Name
         use Asis.Declarations;
         From_Body : Boolean := False;
         Current   : Asis.Element;
         Info      : Package_Info;
         Kind      : Declaration_Check_Kinds;
      begin
         if not Package_Visibles.Is_Present (Name) then
            -- Package is a compilation unit that has not yet been processed
            -- We cannot be in the corresponding body, since a package spec is
            -- always processed before the body
            --    => Not_Movable
            Kind := Declaration_Check_Kind (A4G_Bugs.Corresponding_Name_Declaration (Name));
            if Kind /= Check_Not_Checkable then
               Package_Visibles.Store (Name, (Outside_Used, Kind));
            end if;
            return;
         end if;

         Info := Package_Visibles.Fetch (Name);
         if Info.Usage = Outside_Used then
            return;
         end if;

         -- Search if Name is within the body of the package that contains its
         -- declaration
         Enclosing_Decl := Corresponding_Body (Enclosing_Decl);
         Current        := Enclosing_Element (Name);
         while not Is_Nil (Current) loop
            if Is_Equal (Current, Enclosing_Decl) then
               From_Body := True;
               exit;
            end if;
            Current := Enclosing_Element (Current);
         end loop;

         if From_Body then
            Info.Usage := Body_Used;
         else
            Info.Usage := Outside_Used;
         end if;
         Package_Visibles.Store (Name, Info);
      end Check_Body_Movable_Declaration;

      procedure Check_Movable_Declaration is
         use  Asis.Declarations, Asis.Expressions;
         Name_Def   : Asis.Definition := Corresponding_Name_Definition (Name);
         Info       : Declaration_Info;
         Enclosing  : Asis.Expression;
         Good_Depth : Scope_Range;
         Action     : Merge_Action;
      begin
         if Is_Nil (Name_Def) then
            -- Some predefined stuff
            return;
         end if;

         -- If the name returned by Corresponding_Name_Definition is from a body with an
         -- explicit specification, take the name from the spec
         case Declaration_Kind (Enclosing_Element (Name_Def)) is
            when A_Function_Body_Declaration
              | A_Function_Renaming_Declaration
              | A_Function_Body_Stub
              | A_Package_Body_Declaration
              | A_Package_Body_Stub
              | A_Procedure_Body_Declaration
              | A_Procedure_Renaming_Declaration
              | A_Procedure_Body_Stub
              | A_Task_Body_Declaration
              | A_Task_Body_Stub
              | A_Protected_Body_Declaration
              | A_Protected_Body_Stub
              | A_Formal_Package_Declaration
              | A_Formal_Package_Declaration_With_Box
              | A_Generic_Package_Renaming_Declaration
              | A_Generic_Procedure_Renaming_Declaration
              | A_Generic_Function_Renaming_Declaration
              | An_Entry_Body_Declaration
              =>
               if not Is_Nil (Corresponding_Declaration (Enclosing_Element (Name_Def))) then
                  Name_Def := Names (Corresponding_Declaration (Enclosing_Element (Name_Def))) (1);
               end if;
            when others =>
               null;
         end case;

         -- Kind and Path are ignored below, since Equivalent_Keys compare only Elem
         Local_Declarations.Reset ((Elem  => Name_Def,
                                    Kind  => Check_Kind'First,
                                    Path  => null), Current_Scope_Only);
         if not Local_Declarations.Data_Available then
            -- not found
            return;
         end if;

         Info      := Local_Declarations.Current_Data;
         Enclosing := Enclosing_Element (Name);
         if Expression_Kind (Enclosing) = An_Attribute_Reference
           and then A4G_Bugs.Attribute_Kind (Enclosing) in An_Access_Attribute .. An_Address_Attribute
         then
            -- Name used in 'Access or 'Address, too dangerous to move
            Local_Declarations.Delete_Current;
            return;
         end if;

         if Declaration_Kind (Enclosing) = A_Parameter_Specification then
            -- This name is part of a parameter specification => must be visible outside
            -- Do not consider the innermost scope (i.e. the declaration of the SP it is a parameter of)
            Good_Depth := Current_Depth - 1;
         else
            Good_Depth := Current_Depth;
         end if;

         Merge (Info.Path,
                Active_Scopes (Local_Declarations.Current_Data_Level + 1 .. Good_Depth),
                Blocks_Forbidden => Ctl_Restrictions (Info.Kind)(No_Blocks),
                Action           => Action);
         case Action is
            when Delete =>
               Local_Declarations.Delete_Current;
            when Update =>
               Local_Declarations.Update_Current (Info);
            when Keep =>
               null;
         end case;
      end Check_Movable_Declaration;

      procedure Check_Movable_Use_Clause is
         use Framework.Queries;

         Enclosing_Name : constant Unbounded_Wide_String
           := To_Unbounded_Wide_String (Enclosing_Package_Name (Rule_Id, Name));
         Info       : Use_Info;
         Good_Depth : Scope_Range;
         Action     : Merge_Action;
      begin
         if Enclosing_Name = "" then
            -- Not declared immediately in a package specification
            return;
         end if;

         if Declaration_Kind (Enclosing_Element (Name)) = A_Parameter_Specification then
            -- This name is part of a parameter specification => must be visible outside
            -- Do not consider the innermost scope (i.e. the declaration of the SP it is a parameter of)
            Good_Depth := Current_Depth - 1;
         else
            Good_Depth := Current_Depth;
         end if;

         Use_Clauses.Reset (All_Scopes);
         while Use_Clauses.Data_Available loop
            Info := Use_Clauses.Current_Data;
            if Info.Image = Enclosing_Name then
               Merge (Info.Path,
                      Active_Scopes (Use_Clauses.Current_Data_Level + 1 .. Good_Depth),
                      Blocks_Forbidden => Ctl_Restrictions (Check_Use)(No_Blocks),
                      Action           => Action);
               case Action is
                  when Delete =>
                     Use_Clauses.Delete_Current;
                  when Update =>
                     Use_Clauses.Update_Current (Info);
                     Use_Clauses.Next;
                  when Keep =>
                     Use_Clauses.Next;
               end case;
            else
               Use_Clauses.Next;
            end if;
         end loop;
      end Check_Movable_Use_Clause;

      use Thick_Queries;
      EPU : Asis.Defining_Name;
   begin -- Process_Identifier
      if Rule_Used = No_Check then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if In_Context_Clauses then
         -- nothing here for us
         return;
      end if;

      if (Rule_Used and Check_Kind_Set'(Check_Use => False, others => True)) /= No_Check then
         EPU := Enclosing_Program_Unit (A4G_Bugs.Corresponding_Name_Declaration (Name));
         if Is_Nil (EPU) then
            -- Name is the name of a compilation unit
            return;
         end if;
         Enclosing_Decl := Enclosing_Element (EPU);
         if Declaration_Kind (Enclosing_Decl) = A_Package_Declaration then
            Check_Body_Movable_Declaration;
         else
            Check_Movable_Declaration;
         end if;
      end if;

      if Rule_Used (Check_Use) then
         Check_Movable_Use_Clause;
      end if;
   end Process_Identifier;

   ------------------------
   -- Process_Use_Clause --
   ------------------------

   procedure Process_Use_Clause (Clause : in Asis.Clause) is
      use Asis.Clauses;
      use Thick_Queries;
   begin
      if not Rule_Used (Check_Use) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      declare
         Names : constant Asis.Expression_List := Clause_Names (Clause);
      begin
         for I in Names'Range loop
            Use_Clauses.Push ((Elem  => Names (I),
                               Path  => null,
                               Image => To_Unbounded_Wide_String (To_Upper
                                                                  (Full_Name_Image
                                                                   (Ultimate_Name (Names (I)))))));
         end loop;
      end;
   end Process_Use_Clause;

   ------------------------
   -- Process_Scope_Exit --
   ------------------------

   procedure Process_Scope_Exit (Scope : in Asis.Element) is
      pragma Unreferenced (Scope);
      use Framework.Reports, Thick_Queries;
      use Asis, Asis.Declarations;

      D_Info : Declaration_Info;
      U_Info : Use_Info;

      function Scope_Image (Elem : Asis.Element) return Wide_String is
         use Asis.Elements;
      begin
         case Declaration_Kind (Elem) is
            when A_Procedure_Declaration | A_Procedure_Body_Declaration =>
               return "procedure " & Defining_Name_Image (Names (Elem)(1));
            when A_Function_Declaration | A_Function_Body_Declaration =>
               return "function " & Defining_Name_Image (Names (Elem)(1));
            when A_Package_Declaration | A_Package_Body_Declaration =>
               return "package " & Defining_Name_Image (Names (Elem)(1));
            when others =>
               -- Including Not_A_Declaration
               null;
         end case;

         case Statement_Kind (Elem) is
            when A_Block_Statement =>
               return "block";
            when others =>
               null;
         end case;

         return "scope";
      end Scope_Image;

   begin -- Process_Scope_Exit
      if Rule_Used = No_Check then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Report_All_Package_Names (Scope_Kind => Symbol_Table.Visibility);

      Local_Declarations.Reset (Current_Scope_Only);
      while Local_Declarations.Data_Available loop
         D_Info := Local_Declarations.Current_Data;
         if not Ctl_Restrictions (D_Info.Kind)(To_Body) then
            if D_Info.Path = null then
               Report (Rule_Id,
                       Ctl_Contexts (D_Info.Kind),
                       Get_Location (D_Info.Elem),
                       Defining_Name_Image (D_Info.Elem) & " is not used");
            else
               Report (Rule_Id,
                       Ctl_Contexts (D_Info.Kind),
                       Get_Location (D_Info.Elem),
                       "declaration of " & Defining_Name_Image (D_Info.Elem)
                       & " can be moved inside " & Scope_Image (D_Info.Path (D_Info.Path'Last))
                       & " at " & Image (Get_Location (D_Info.Path (D_Info.Path'Last))));
            end if;
         end if;

         Local_Declarations.Next;
      end loop;

      Use_Clauses.Reset (Current_Scope_Only);
      while Use_Clauses.Data_Available loop
         U_Info := Use_Clauses.Current_Data;
         if not Ctl_Restrictions (Check_Use) (To_Body) then
            if U_Info.Path = null then
               Report (Rule_Id,
                       Ctl_Contexts (Check_Use),
                       Get_Location (U_Info.Elem),
                       "Use clause for " & Extended_Name_Image (U_Info.Elem) & " is not necessary");
            else
               Report (Rule_Id,
                       Ctl_Contexts (Check_Use),
                       Get_Location (U_Info.Elem),
                       "use clause for " & Extended_Name_Image (U_Info.Elem)
                       & " can be moved inside " & Scope_Image (U_Info.Path (U_Info.Path'Last))
                       & " at " & Image (Get_Location (U_Info.Path (U_Info.Path'Last))));
            end if;
         end if;

         Use_Clauses.Next;
      end loop;
   end Process_Scope_Exit;

   --------------
   -- Finalize --
   --------------

   procedure Finalize is
   begin
      if Rule_Used = No_Check then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      -- Report on declarations from library packages
      Report_All_Package_Names (Scope_Kind => Symbol_Table.Visibility);

      Package_Visibles.Clear;
   end Finalize;

begin  -- Rules.Reduceable_Scope
   Framework.Rules_Manager.Register (Rule_Id,
                                     Rules_Manager.Semantic,
                                     Help_CB        => Help'Access,
                                     Add_Control_CB => Add_Control'Access,
                                     Command_CB     => Command'Access,
                                     Prepare_CB     => Prepare'Access,
                                     Finalize_CB    => Finalize'Access);
end Rules.Reduceable_Scope;
