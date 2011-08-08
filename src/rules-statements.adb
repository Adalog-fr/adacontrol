----------------------------------------------------------------------
--  Rules.Statement - Package body                                  --
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

-- ASIS
with
  Asis.Compilation_Units,
  Asis.Declarations,
  Asis.Elements,
  Asis.Iterator,
  Asis.Statements;

-- Adalog
with
  Thick_Queries,
  Utilities;

-- Adactl
with
  Framework.Language,
  Framework.Rules_Manager,
  Framework.Reports,
  Framework.Scope_Manager;
pragma Elaborate (Framework.Language);

package body Rules.Statements is
   use Framework;

   type Subrules is (Stmt_Abort,                  Stmt_Accept_Return,          Stmt_Assignment,
                     Stmt_Asynchronous_Select,    Stmt_Block,                  Stmt_Case,
                     Stmt_Case_Others,            Stmt_Case_Others_Null,       Stmt_Code,
                     Stmt_Conditional_Entry_Call, Stmt_Declare_Block,          Stmt_Delay,
                     Stmt_Delay_Until,            Stmt_Dispatching_Call,       Stmt_Effective_Declare_Block,
                     Stmt_Entry_Return,
                     Stmt_Exception_Others,       Stmt_Exception_Others_Null,  Stmt_Exit,
                     Stmt_Exit_For_Loop,          Stmt_Exit_While_Loop,        Stmt_For_Loop,
                     Stmt_Function_Return,        Stmt_Goto,                   Stmt_If,
                     Stmt_If_Elsif,               Stmt_Labelled,               Stmt_Loop_Return,
                     Stmt_Multiple_Exits,         Stmt_No_Else,                Stmt_Null,
                     Stmt_Procedure_Return,       Stmt_Raise,                  Stmt_Raise_Standard,
                     Stmt_Requeue,                Stmt_Reraise,                Stmt_Selective_Accept,
                     Stmt_Simple_Loop,            Stmt_Terminate,              Stmt_Timed_Entry_Call,
                     Stmt_Unconditional_Exit,     Stmt_Unnamed_Block,          Stmt_Unnamed_Exit,
                     Stmt_Unnamed_Loop_Exited,    Stmt_Unnamed_For_Loop,       Stmt_Unnamed_Multiple_Loop,
                     Stmt_Unnamed_Simple_Loop,    Stmt_Unnamed_While_Loop,     Stmt_Untyped_For,
                     Stmt_While_Loop);

   package Subrules_Flags_Utilities is new Framework.Language.Flag_Utilities (Subrules, "STMT_");
   use Subrules_Flags_Utilities;

   type Usage_Flags is array (Subrules) of Boolean;
   Rule_Used : Usage_Flags := (others => False);
   Save_Used : Usage_Flags;
   Usage     : array (Subrules) of Basic_Rule_Context;

   -- For Stmt_Unnamed_Multiple_Loop:
   type Loops_Level is range 0 .. Max_Loop_Nesting;
   Body_Depth  : Framework.Scope_Manager.Scope_Range := 0;
   Loops_Depth : array (Framework.Scope_Manager.Scope_Range) of Loops_Level;
   Top_Loop    : array (Framework.Scope_Manager.Scope_Range) of Asis.Statement;

   ----------
   -- Help --
   ----------

   procedure Help is
      use Utilities;
   begin
      User_Message  ("Rule: " & Rule_Id);
      Help_On_Flags ("Parameter(s):");
      User_Message  ("Control occurrences of Ada statements");
   end Help;

   -----------------
   -- Add_Control --
   -----------------

   procedure Add_Control (Ctl_Label : in Wide_String; Ctl_Kind : in Control_Kinds) is
      use Framework.Language;
      Subrule : Subrules;

   begin
      if not Parameter_Exists then
         Parameter_Error (Rule_Id, "at least one parameter required");
      end if;

      while Parameter_Exists loop
         Subrule := Get_Flag_Parameter (Allow_Any => False);
         if Rule_Used (Subrule) then
            Parameter_Error (Rule_Id, "statement already given: " & Image (Subrule));
         end if;

         Rule_Used (Subrule) := True;
         Usage (Subrule)     := Basic.New_Context (Ctl_Kind, Ctl_Label);
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
            Rule_Used  := (others => False);
         when Suspend =>
            Save_Used := Rule_Used;
            Rule_Used := (others => False);
         when Resume =>
            Rule_Used := Save_Used;
      end case;
   end Command;


   -----------------------
   -- Process_Statement --
   -----------------------

   procedure Process_Statement (Element : in Asis.Statement) is
      use Asis, Asis.Compilation_Units, Asis.Declarations, Asis.Elements, Asis.Statements;
      use Thick_Queries, Utilities;

      procedure Do_Report (Stmt : in Subrules; Loc : Location := Get_Location (Element)) is
         use Framework.Reports;
      begin
         if not Rule_Used (Stmt) then
            return;
         end if;

         Report (Rule_Id,
                 Usage (Stmt),
                 Loc,
                 "use of statement """ & Image (Stmt) & '"');
      end Do_Report;

   begin
      if Rule_Used = (Subrules => False) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if not Is_Nil (Label_Names (Element)) then
         Do_Report (Stmt_Labelled);
      end if;

      case Statement_Kind (Element) is
         when Not_A_Statement =>
            Failure ("Not a statement");

         when An_Abort_Statement =>
            Do_Report (Stmt_Abort);

         when An_Accept_Statement =>
            null;

         when An_Assignment_Statement =>
            Do_Report (Stmt_Assignment);

         when An_Asynchronous_Select_Statement =>
            Do_Report (Stmt_Asynchronous_Select);

         when A_Block_Statement =>
            Do_Report (Stmt_Block);
            if Is_Nil (Statement_Identifier (Element)) then
               Do_Report (Stmt_Unnamed_Block);
            end if;
            if Is_Declare_Block (Element) then
               Do_Report (Stmt_Declare_Block);
               if Rule_Used (Stmt_Effective_Declare_Block) then
                  declare
                     Decls : constant Asis.Declarative_Item_List := Block_Declarative_Items (Element,
                                                                                              Include_Pragmas => False);
                  begin
                     for D in Decls'Range loop
                        if Clause_Kind (Decls (D)) not in A_Use_Package_Clause .. A_Use_Type_Clause then
                           Do_Report (Stmt_Effective_Declare_Block);
                           exit;
                        end if;
                     end loop;
                  end;
               end if;
            end if;

         when A_Case_Statement =>
            Do_Report (Stmt_Case);

         when A_Code_Statement =>
            Do_Report (Stmt_Code);

         when A_Conditional_Entry_Call_Statement =>
            Do_Report (Stmt_Conditional_Entry_Call);

         when A_Delay_Relative_Statement =>
            Do_Report (Stmt_Delay);

         when A_Delay_Until_Statement =>
            Do_Report (Stmt_Delay_Until);

         when An_Entry_Call_Statement =>
            null;

         when An_Exit_Statement =>
            declare
               Exited_Loop : constant Asis.Statement := Corresponding_Loop_Exited (Element);
            begin
               if Is_Nil (Exit_Condition (Element)) then
                  Do_Report (Stmt_Unconditional_Exit);
               end if;

               if Is_Nil (Statement_Identifier (Exited_Loop)) then
                  Do_Report (Stmt_Unnamed_Loop_Exited);
               elsif Is_Nil (Exit_Loop_Name (Element)) then
                  Do_Report (Stmt_Unnamed_Exit);
               end if;

               if Rule_Used (Stmt_Exit_For_Loop)
                 and then Statement_Kind (Exited_Loop) = A_For_Loop_Statement
               then
                  Do_Report (Stmt_Exit_For_Loop);
               elsif Rule_Used (Stmt_Exit_While_Loop)
                 and then Statement_Kind (Exited_Loop) = A_While_Loop_Statement
               then
                  Do_Report (Stmt_Exit_While_Loop);
               else
                  Do_Report (Stmt_Exit);
               end if;
            end;

         when A_For_Loop_Statement =>
            Do_Report (Stmt_For_Loop);

            if Is_Nil (Statement_Identifier (Element)) then
               Do_Report (Stmt_Unnamed_For_Loop);
            end if;

            if Discrete_Range_Kind (Specification_Subtype_Definition
                                    (For_Loop_Parameter_Specification
                                     (Element))) = A_Discrete_Simple_Expression_Range
            then
               Do_Report (Stmt_Untyped_For);
            end if;

         when A_Goto_Statement =>
            Do_Report (Stmt_Goto);

         when An_If_Statement =>
            Do_Report (Stmt_If);
            declare
               Paths : constant Asis.Path_List := Statement_Paths (Element);
            begin
               if Path_Kind (Paths (Paths'Last)) /= An_Else_Path then
                  Do_Report (Stmt_No_Else);
               end if;
               if Paths'Length >= 2 and then Path_Kind (Paths (2)) = An_Elsif_Path then
                  Do_Report (Stmt_If_Elsif);
               end if;
            end;

         when A_Loop_Statement =>
            Do_Report (Stmt_Simple_Loop);

            if Is_Nil (Statement_Identifier (Element)) then
               Do_Report (Stmt_Unnamed_Simple_Loop);
            end if;

         when A_Null_Statement =>
            Do_Report (Stmt_Null);

         when A_Procedure_Call_Statement =>
            if Is_Dispatching_Call (Element) then
               Do_Report (Stmt_Dispatching_Call);
            end if;

         when A_Raise_Statement =>
            declare
               Exc : constant Asis.Expression := Raised_Exception (Element);
            begin
               if Is_Nil (Exc) then
                  if Rule_Used (Stmt_Reraise) then
                     Do_Report (Stmt_Reraise);
                  else
                     Do_Report (Stmt_Raise);
                  end if;
               elsif To_Upper (Unit_Full_Name (Definition_Compilation_Unit (Exc))) = "STANDARD" then
                  if Rule_Used (Stmt_Raise_Standard) then
                     Do_Report (Stmt_Raise_Standard);
                  else
                     Do_Report (Stmt_Raise);
                  end if;
               else
                  Do_Report (Stmt_Raise);
               end if;
            end;

         when A_Requeue_Statement | A_Requeue_Statement_With_Abort =>
            Do_Report (Stmt_Requeue);

         when A_Return_Statement =>
            if Loops_Depth (Body_Depth) > 0 then
               Do_Report (Stmt_Loop_Return);
            end if;
            case Declaration_Kind (Enclosing_Element
                                   (Enclosing_Program_Unit (Element, Including_Accept => True)))
            is
               when A_Procedure_Body_Declaration =>
                  Do_Report (Stmt_Procedure_Return);
               when An_Entry_Declaration =>
                  Do_Report (Stmt_Accept_Return);
               when A_Function_Body_Declaration =>
                  -- Function_Return is checked from Process_Function_Body
                  null;
               when An_Entry_Body_Declaration =>
                  Do_Report (Stmt_Entry_Return);
               when others =>
                  Failure ("Return not from subprogram");
            end case;

         when A_Selective_Accept_Statement =>
            Do_Report (Stmt_Selective_Accept);

         when A_Terminate_Alternative_Statement =>
            Do_Report (Stmt_Terminate);

         when A_Timed_Entry_Call_Statement =>
            Do_Report (Stmt_Timed_Entry_Call);

         when A_While_Loop_Statement =>
            Do_Report (Stmt_While_Loop);

            if Is_Nil (Statement_Identifier (Element)) then
               Do_Report (Stmt_Unnamed_While_Loop);
            end if;

         when others =>
            -- Ada 2005 : An_Extended_Return_Statement
            null;
      end case;
   end Process_Statement;


   --------------------
   -- Process_Others --
   --------------------

   procedure Process_Others (Definition : in Asis.Definition) is
      use Asis, Asis.Elements, Asis.Statements;
      use Framework.Reports, Thick_Queries;
      Encl : Asis.Element;

   begin
      if not Rule_Used (Stmt_Case_Others)
        and not Rule_Used (Stmt_Case_Others_Null)
        and not Rule_Used (Stmt_Exception_Others_Null)
      then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Encl := Enclosing_Element (Definition);
      if  Element_Kind (Encl) = An_Exception_Handler then
         if Rule_Used (Stmt_Exception_Others_Null)
           and then Are_Null_Statements (Handler_Statements (Encl))
         then
            Report (Rule_Id,
                    Usage (Stmt_Exception_Others_Null),
                    Get_Location (Definition),
                    "null ""when others"" exception handler");
         elsif Rule_Used (Stmt_Exception_Others) then
            Report (Rule_Id,
                    Usage (Stmt_Exception_Others),
                    Get_Location (Definition),
                    "use of ""when others"" exception handler");
         end if;

      elsif Path_Kind (Enclosing_Element (Definition)) = A_Case_Path then
         if Rule_Used (Stmt_Case_Others_Null)
           and then Are_Null_Statements (Sequence_Of_Statements (Encl))
         then
            Report (Rule_Id,
                    Usage (Stmt_Case_Others_Null),
                    Get_Location (Definition),
                    "null ""when others"" in ""case"" statement");
         elsif Rule_Used (Stmt_Case_Others) then
            Report (Rule_Id,
                    Usage (Stmt_Case_Others),
                    Get_Location (Definition),
                    "use of ""when others"" in ""case"" statement");
         end if;
      end if;
   end Process_Others;

   ---------------------------
   -- Process_Function_Body --
   ---------------------------

   procedure Process_Function_Body (Function_Body : in Asis.Declaration) is
      use Asis, Asis.Declarations, Asis.Iterator, Asis.Statements;

      First_Return : Asis.Statement;

      procedure Pre_Procedure (Element : in     Asis.Element;
                               Control : in out Traverse_Control;
                               State   : in out Null_State);
      procedure Check is new Traverse_Element (Null_State, Pre_Procedure, Null_State_Procedure);

      procedure Pre_Procedure (Element : in     Asis.Element;
                               Control : in out Traverse_Control;
                               State   : in out Null_State)
      is
         use Asis.Elements;
         use Framework.Reports;
      begin
         case Statement_Kind (Element) is
            when A_Return_Statement =>
               if Is_Nil (First_Return) then
                  First_Return := Element;
               else
                  Report (Rule_Id,
                          Usage (Stmt_Function_Return),
                          Get_Location (Element),
                          "return statement already given at " & Image (Get_Location (First_Return)));
               end if;
            when A_Block_Statement =>
               -- Traverse only the statements part
               declare
                  Block_Stmts : constant Asis.Statement_List := Block_Statements (Element);
               begin
                  for I in Block_Stmts'Range loop
                     Check (Block_Stmts (I), Control, State);
                  end loop;
                  Control := Abandon_Children;
               end;
            when others =>
               -- including Not_A_Statement
               null;
         end case;
      end Pre_Procedure;

      State   : Null_State;
      Control : Traverse_Control;
   begin
      if not Rule_Used (Stmt_Function_Return) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      declare
         Body_Stmts : constant Asis.Statement_List := Body_Statements (Function_Body);
      begin
         First_Return := Nil_Element;
         Control      := Continue;
         for I in Body_Stmts'Range loop
            Check (Body_Stmts (I), Control, State);
         end loop;
      end;

      declare
         Handlers : constant Asis.Exception_Handler_List := Body_Exception_Handlers (Function_Body);
      begin
         for H in Handlers'Range loop
            declare
               Handler_Stmts : constant Asis.Statement_List := Handler_Statements (Handlers (H));
            begin
               First_Return := Nil_Element;
               Control      := Continue;
              for I in Handler_Stmts'Range loop
                  Check (Handler_Stmts (I), Control, State);
               end loop;
            end;
         end loop;
      end;
   end Process_Function_Body;

   ---------------------------
   -- Process_Function_Call --
   ---------------------------

   procedure Process_Function_Call (Call : in Asis.Expression) is
      use Asis.Statements;
      use Framework.Reports;
   begin
      if not Rule_Used (Stmt_Dispatching_Call) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if Is_Dispatching_Call (Call) then
         Report (Rule_Id,
                 Usage (Stmt_Dispatching_Call),
                 Get_Location (Call),
                 "use of statement """ & Image (Stmt_Dispatching_Call) & '"');
      end if;
   end Process_Function_Call;


   --------------------------
   -- Process_Loop_Statements
   --------------------------

   procedure Process_Loop_Statements (In_Loop : in Asis.Statement) is
      use Asis, Asis.Iterator, Asis.Statements;

      First_Exit : Asis.Statement;

      type State_Info is
      record
         Loop_Statement : Statement;
      end record;

      procedure Pre_Procedure (Element : in     Asis.Element;
                               Control : in out Traverse_Control;
                               State   : in out State_Info);
      procedure Post_Procedure (Element : in     Asis.Element;
                                Control : in out Traverse_Control;
                                State   : in out State_Info);
      procedure Check is new Traverse_Element (State_Info, Pre_Procedure, Post_Procedure);

      procedure Pre_Procedure (Element : in     Asis.Element;
                               Control : in out Traverse_Control;
                               State   : in out State_Info)
      is
         use Asis.Elements;
         use Framework.Reports;
      begin
         case Statement_Kind (Element) is
            when An_Exit_Statement =>
               if Is_Identical (Corresponding_Loop_Exited (Element), State.Loop_Statement) then
                  if Is_Nil (First_Exit) then
                     First_Exit := Element;
                  else
                     Report (Rule_Id,
                             Usage (Stmt_Multiple_Exits),
                             Get_Location (Element),
                             "exit statement already given at " & Image (Get_Location (First_Exit)));
                  end if;
               end if;
            when A_Block_Statement =>
               -- Traverse only the statements and exceptions parts
               declare
                  Block_Stmts : constant Asis.Statement_List := Block_Statements (Element);
               begin
                  for I in Block_Stmts'Range loop
                     Check (Block_Stmts (I), Control, State);
                  end loop;
               end;

               declare
                  Block_Handlers : constant Asis.Exception_Handler_List := Block_Exception_Handlers (Element);
               begin
                  for H in Block_Handlers'Range loop
                     declare
                        Handler_Stmts : constant Asis.Statement_List := Handler_Statements (Block_Handlers (H));
                     begin
                        for I in Handler_Stmts'Range loop
                           Check (Handler_Stmts (I), Control, State);
                        end loop;
                     end;
                  end loop;
               end;
               Control := Abandon_Children;
            when others =>
               -- including Not_A_Statement
               null;
         end case;
      end Pre_Procedure;

      procedure Post_Procedure (Element : in     Asis.Element;
                                Control : in out Traverse_Control;
                                State   : in out State_Info) is
         pragma Unreferenced (Element, Control, State);
      begin
         null;
      end Post_Procedure;

      State   : State_Info := (Loop_Statement => In_Loop);
      Control : Traverse_Control;
   begin
      declare
         Loop_Stmts : constant Asis.Statement_List := Loop_Statements (In_Loop);
      begin
         First_Exit := Nil_Element;
         Control    := Continue;
         for I in Loop_Stmts'Range loop
            Check (Loop_Stmts (I), Control, State);
         end loop;
      end;
   end Process_Loop_Statements;

   ----------------------
   -- Pre_Process_Loop --
   ----------------------

   procedure Pre_Process_Loop  (Stmt : in Asis.Statement) is
      use Asis, Asis.Elements, Asis.Statements;
      use Framework.Reports, Utilities;
   begin
      if not Rule_Used (Stmt_Unnamed_Multiple_Loop)
        and not Rule_Used (Stmt_Multiple_Exits)
        and not Rule_Used (Stmt_Loop_Return)
      then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if Rule_Used (Stmt_Multiple_Exits) then
         Process_Loop_Statements (Stmt);
      end if;

      if Loops_Depth (Body_Depth) = Loops_Level'Last then
         Failure ("Loops nesting deeper than maximum allowed:"
                  & Loops_Level'Wide_Image (Max_Loop_Nesting),
                  Element => Stmt);
      end if;
      Loops_Depth (Body_Depth) := Loops_Depth (Body_Depth) + 1;
      if Loops_Depth (Body_Depth) = 1 then
         Top_Loop (Body_Depth) := Stmt;
         return;
      end if;

      -- It is a nested loop here

      if Rule_Used (Stmt_Unnamed_Multiple_Loop) then
         if not Is_Nil (Top_Loop (Body_Depth)) then
            if Is_Nil (Statement_Identifier (Top_Loop (Body_Depth))) then
               Report (Rule_Id,
                       Usage (Stmt_Unnamed_Multiple_Loop),
                       Get_Location (Top_Loop (Body_Depth)),
                       "Outer loop is not named, inner loop at " & Image (Get_Location (Stmt)));
            end if;
            Top_Loop (Body_Depth) := Nil_Element;
         end if;

         if Is_Nil (Statement_Identifier (Stmt)) then
            Report (Rule_Id,
                    Usage (Stmt_Unnamed_Multiple_Loop),
                    Get_Location (Stmt),
                    "Nested loop is not named");
         end if;
      end if;
   end Pre_Process_Loop;

   -----------------------
   -- Post_Process_Loop --
   -----------------------

   procedure Post_Process_Loop (Stmt : in Asis.Statement) is
      pragma Unreferenced (Stmt);
   begin
      if not Rule_Used (Stmt_Unnamed_Multiple_Loop)
        and not Rule_Used (Stmt_Multiple_Exits)
        and not Rule_Used (Stmt_Loop_Return)
      then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Loops_Depth (Body_Depth) := Loops_Depth (Body_Depth) - 1;
   end Post_Process_Loop;

   -------------------------
   -- Process_Scope_Enter --
   -------------------------

   procedure Process_Scope_Enter (Scope : in Asis.Statement) is
      use Asis, Asis.Elements;
      use Framework.Scope_Manager;
   begin
      if Rule_Used = (Subrules => False) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      -- Check scopes that are not "bodies"
      case Element_Kind (Scope) is
         when An_Exception_Handler =>
            return;
         when A_Statement =>
            if Statement_Kind (Scope) /= An_Accept_Statement then
               return;
            end if;
         when others =>
            null;
      end case;

      Body_Depth               := Body_Depth + 1;
      Loops_Depth (Body_Depth) := 0;
   end Process_Scope_Enter;

   ------------------------
   -- Process_Scope_Exit --
   ------------------------

   procedure Process_Scope_Exit  (Scope : in Asis.Statement) is
      use Asis, Asis.Elements;
      use Framework.Scope_Manager;
   begin
      if Rule_Used = (Subrules => False) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      -- Check scopes that are not "bodies"
      case Element_Kind (Scope) is
         when An_Exception_Handler =>
            return;
         when A_Statement =>
            if Statement_Kind (Scope) /= An_Accept_Statement then
               return;
            end if;
         when others =>
            null;
      end case;

      Body_Depth := Body_Depth - 1;
   end Process_Scope_Exit;


   ----------------
   -- Enter_Unit --
   ----------------

   procedure Enter_Unit (Unit : in Asis.Compilation_Unit) is
      use Asis, Asis.Compilation_Units;
   begin
      if Unit_Kind (Unit) not in A_Subunit then
         -- In normal cases, Body_Depth from processing previous units has returned to 0 when
         -- we enter a top-level unit (not a subunit).
         -- However, if a previous unit failed, Body_Depth is left at a possible non-zero value.
         -- If we have several failures, we may end up in Constraint_Error.
         -- So, stay on the safe side and force resetting in all cases.
         Body_Depth := 0;
      end if;
   end Enter_Unit;

begin
   Framework.Rules_Manager.Register (Rule_Id,
                                     Rules_Manager.Semantic,
                                     Help_CB        => Help'Access,
                                     Add_Control_CB => Add_Control'Access,
                                     Command_CB     => Command'Access);
end Rules.Statements;
