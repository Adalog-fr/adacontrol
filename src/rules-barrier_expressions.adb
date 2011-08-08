----------------------------------------------------------------------
--  Rules.Barrier_Expressions - Package body                        --
--                                                                  --
--  This software  is (c) Adalog  2004-2005. The Ada  Controller is --
--  free software;  you can redistribute it and/or  modify it under --
--  terms of  the GNU  General Public License  as published  by the --
--  Free Software Foundation; either version 2, or (at your option) --
--  any later version.   This unit is distributed in  the hope that --
--  it will be  useful, but WITHOUT ANY WARRANTY;  without even the --
--  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR --
--  PURPOSE.  See the GNU  General Public License for more details. --
--  You  should have  received a  copy  of the  GNU General  Public --
--  License distributed  with this  program; see file  COPYING.  If --
--  not, write to  the Free Software Foundation, 59  Temple Place - --
--  Suite 330, Boston, MA 02111-1307, USA.                          --
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
  Ada.Strings.Wide_Unbounded;

-- Asis
with
  Asis.Declarations,
  Asis.Definitions,
  Asis.Elements,
  Asis.Expressions;

-- Adalog
with
  A4G_Bugs,
  Thick_Queries,
  Utilities;

-- AdaControl
with
  Framework,
  Framework.Reports,
  Framework.Rules_Manager,
  Framework.Language;
pragma Elaborate (Framework.Language);

package body Rules.Barrier_Expressions is
   use Framework;

   type Keyword is (K_Entity,              K_Allocation,          K_Any_Component,
                    K_Any_Variable,        K_Arithmetic_Operator, K_Array_Aggregate,
                    K_Comparison_Operator, K_Conversion,          K_Dereference,
                    K_Indexing,            K_Function_Attribute,  K_Local_Function,
                    K_Logical_Operator,    K_Record_Aggregate,    K_Value_Attribute);
   package Keyword_Flag_Utilities is new Framework.Language.Flag_Utilities (Keyword, "K_");

   -- In the following record, Types (K) is true if the check must be performed for K,
   -- i.e. the <entity> is /not/ allowed for K
   type Key_Context is new Root_Context with
      record
         Types : Control_Kinds_Set;
      end record;
   Contexts  : Context_Store;

   Rule_Used : Control_Kinds_Set := (others => False);
   Save_Used : Control_Kinds_Set;
   Labels    : array (Control_Kinds) of Ada.Strings.Wide_Unbounded.Unbounded_Wide_String;

   ----------
   -- Help --
   ----------

   procedure Help is
      use Utilities, Keyword_Flag_Utilities;
   begin
      User_Message  ("Rule: " & Rule_Id);
      Help_On_Flags ("Parameter(s):", Extra_Value => "<entity>");
      User_Message  ("Control constucts used in protected entry barriers");
   end Help;


   -----------------
   -- Add_Control --
   -----------------

   procedure Add_Control (Ctl_Label : in Wide_String; Ctl_Kind : in Control_Kinds) is
      use Ada.Strings.Wide_Unbounded;
      use Framework.Language, Keyword_Flag_Utilities, Utilities;

      Key  : Keyword;
      Spec : Entity_Specification;
      Cont : Key_Context;
   begin
      if Rule_Used (Ctl_Kind) then
         Parameter_Error (Rule_Id,  "rule already specified for " & To_Lower (Control_Kinds'Wide_Image (Ctl_Kind)));
      end if;
      Cont.Types            := (others => True);
      Cont.Types (Ctl_Kind) := False;

      while Parameter_Exists loop
         Key := Get_Flag_Parameter (Allow_Any => True);

         if Key = K_Entity then
            Spec := Get_Entity_Parameter;
         else
            Spec := Value (Image (Key));
         end if;

         begin
            Associate (Contexts, Spec, Cont);
         exception
            when Already_In_Store =>
               Cont := Key_Context (Association (Contexts, Spec));
               if Cont.Types (Ctl_Kind) then
                  Cont.Types (Ctl_Kind) := False;
                  Update (Contexts, Cont);
               else
                  Parameter_Error (Rule_Id, "parameter already provided for "
                                     & To_Lower (Control_Kinds'Wide_Image (Ctl_Kind))
                                     & ": " & Image (Spec));
               end if;
         end;
      end loop;

      Labels    (Ctl_Kind) := To_Unbounded_Wide_String (Ctl_Label);
      Rule_Used (Ctl_Kind) := True;
   end Add_Control;


   -------------
   -- Command --
   -------------

   procedure Command (Action : in Framework.Rules_Manager.Rule_Action) is
      use Framework.Rules_Manager;
   begin
      case Action is
         when Clear =>
            Rule_Used := (others => False);
            Clear (Contexts);
         when Suspend =>
            Save_Used := Rule_Used;
            Rule_Used := (others => False);
         when Resume =>
            Rule_Used := Save_Used;
      end case;
   end Command;


   -------------------------------
   -- Process_Entry_Declaration --
   -------------------------------

   procedure Process_Entry_Declaration (Decl : in Asis.Declaration) is
      use Asis.Declarations;

      procedure Check_Expression (Exp : in Asis.Expression) is
         use Asis, Asis.Definitions, Asis.Elements, Asis.Expressions;
         use Keyword_Flag_Utilities, Thick_Queries, Utilities;

         procedure Do_Report (Message    : in Wide_String;
                              Context    : in Root_Context'Class;
                              Identifier : in Asis.Element := Nil_Element;
                              Loc        : in Location := Get_Location (Exp))
         is
            use Framework.Reports, Ada.Strings.Wide_Unbounded;
            S : Control_Kinds_Set;
         begin
            if Context = No_Matching_Context then
               if Is_Nil (Identifier) then
                  S := Rule_Used;
               else
                  declare
                     Alternate_Context : constant Root_Context'Class := Matching_Context (Contexts, Identifier);
                  begin
                     if Alternate_Context = No_Matching_Context then
                        S := Rule_Used;
                     else
                        S := Key_Context (Alternate_Context).Types and Rule_Used;
                     end if;
                  end;
               end if;
            else
               S := Key_Context (Context).Types and Rule_Used;
            end if;

            if S (Check) then
               Report (Rule_Id, To_Wide_String (Labels (Check)), Check, Loc, Message);
            elsif S (Search) then
               Report (Rule_Id, To_Wide_String (Labels (Search)), Search, Loc, Message);
            end if;

            if S (Count) then
               Report (Rule_Id, To_Wide_String (Labels (Count)), Count, Loc, "");
            end if;
         end Do_Report;

      begin   -- Check_Expression
         case Expression_Kind (Exp) is
            when Not_An_Expression =>
               Failure (Rule_Id & ": Not_An_Expression");

            when An_Identifier =>
               declare
                  Name_Decl : constant Asis.Declaration := Corresponding_Name_Declaration (Exp);
               begin
                  case Declaration_Kind (Name_Decl) is
                     when A_Package_Declaration
                        | A_Package_Body_Declaration
                        | A_Protected_Type_Declaration
                          =>
                          -- Can appear only as prefix => Harmless
                          null;
                     when A_Function_Declaration
                        | A_Function_Body_Declaration
                          =>
                        -- Since we are in a barrier expression, a function name can appear only as
                        -- a call, not as a prefix of an internal element
                        declare
                           Temp_Elem : Asis.Element := Enclosing_Element (Name_Decl);
                           Is_Local  : Boolean;
                        begin
                           if Definition_Kind (Temp_Elem) = A_Protected_Definition then
                              -- It is a call to a protected function, but does it belong to the same PO?
                              Temp_Elem := Enclosing_Element (Exp);
                              while Expression_Kind (Temp_Elem) /= A_Function_Call loop
                                 Temp_Elem := Enclosing_Element (Temp_Elem);
                              end loop;
                              Is_Local := Is_Nil (External_Call_Target (Temp_Elem));
                           else
                              Is_Local := False;
                           end if;
                           if Is_Local then
                              Do_Report ("local function call",
                                         Framework.Association (Contexts, Image (K_Local_Function)),
                                         Exp);
                           else
                              Do_Report ("non-local function call", Matching_Context (Contexts, Exp));
                           end if;
                        end;
                     when A_Variable_Declaration
                        | A_Single_Protected_Declaration
                        | A_Loop_Parameter_Specification  -- Consider this (and next) as variables,
                        | An_Entry_Index_Specification    -- although they are strictly speaking constants
                          =>
                        Do_Report ("variable",
                                   Framework.Association (Contexts, Image (K_Any_Variable)),
                                   Exp);
                     when A_Component_Declaration =>
                        -- This can be:
                        --   A component of a protected element: boolean fields always allowed, others checked
                        --   A component of a record type: nothing to check, the check is performed on the data
                        --      that encloses the component.
                        if Definition_Kind (Enclosing_Element (Name_Decl)) = A_Protected_Definition then
                           -- A field of the protected element, boolean fields always allowed
                           if To_Upper (Full_Name_Image
                                        (Subtype_Simple_Name
                                         (Component_Subtype_Indication
                                          (Object_Declaration_View (Name_Decl)))))
                             /= "STANDARD.BOOLEAN"
                           then
                              Do_Report ("non-boolean protected component",
                                         Framework.Association (Contexts, Image (K_Any_Component)),
                                         Exp);
                           end if;
                        end if;
                     when A_Constant_Declaration
                        | A_Number_Declaration
                          =>
                        -- always allowed
                        null;
                     when others =>
                        Failure (Rule_Id
                                 & ": unexpected declaration kind "
                                 & Declaration_Kinds'Wide_Image (Declaration_Kind (Name_Decl)),
                                 Exp);
                  end case;
               end;
            when An_Integer_Literal
              | A_String_Literal
              | A_Real_Literal
              | A_Character_Literal
              | An_Enumeration_Literal
              | A_Null_Literal
              =>
               -- always allowed
               null;

            when An_Operator_Symbol =>
               case Operator_Kind (Exp) is
                  when Not_An_Operator =>
                     Failure (Rule_Id & ": Not_An_Operator");
                  when An_And_Operator
                    | An_Or_Operator
                    | An_Xor_Operator
                    | A_Not_Operator
                    =>
                     -- Check that the operator is a language predefined operator
                     if Is_Nil (A4G_Bugs.Corresponding_Called_Function (Enclosing_Element (Exp))) then
                        -- Predefined operator
                        Do_Report ("predefined logical operator",
                                   Framework.Association (Contexts, Image (K_Logical_Operator)));
                     else
                        -- User defined operator
                        Do_Report ("redefined logical operator",
                                   Matching_Context (Contexts, Exp));
                     end if;
                  when An_Equal_Operator
                    | A_Not_Equal_Operator
                    | A_Less_Than_Operator
                    | A_Less_Than_Or_Equal_Operator
                    | A_Greater_Than_Operator
                    | A_Greater_Than_Or_Equal_Operator
                    =>
                     if Is_Nil (A4G_Bugs.Corresponding_Called_Function (Enclosing_Element (Exp))) then
                        -- Predefined operator
                        Do_Report ("predefined comparison operator",
                          Framework.Association (Contexts,
                                                 Image (K_Comparison_Operator)));
                     else
                        -- User defined operator
                        Do_Report ("redefined comparison operator",
                                   Matching_Context (Contexts, Exp));
                     end if;
                  when others =>
                     if Is_Nil (A4G_Bugs.Corresponding_Called_Function (Enclosing_Element (Exp))) then
                        -- Predefined operator
                        Do_Report ("predefined arithmetic operator",
                          Framework.Association (Contexts,
                                                 Image (K_Arithmetic_Operator)));
                     else
                        -- User defined operator
                        Do_Report ("redefined arithmetic operator",
                                   Matching_Context (Contexts, Exp));
                     end if;
               end case;

            when An_Attribute_Reference =>
               -- Attributes that are not callable entities are always allowed
               if Is_Callable_Construct (Exp) then
                  Do_Report ("callable attribute",
                             Framework.Association (Contexts, Image (K_Function_Attribute)),
                             Exp);
               else
                  Do_Report ("value attribute",
                             Framework.Association (Contexts, Image (K_Value_Attribute)),
                             Exp);
               end if;

            when An_And_Then_Short_Circuit
              | An_Or_Else_Short_Circuit
              =>
               Do_Report ("short-circuit control form",
                          Framework.Association (Contexts, Image (K_Logical_Operator)),
                          Loc => Get_Next_Word_Location (Short_Circuit_Operation_Left_Expression (Exp)));

               -- Check left and right expressions
               Check_Expression (Short_Circuit_Operation_Left_Expression (Exp));
               Check_Expression (Short_Circuit_Operation_Right_Expression (Exp));

            when A_Parenthesized_Expression =>
               -- Check the expression within parenthesis
               Check_Expression (Expression_Parenthesized (Exp));

            when A_Record_Aggregate =>
               Do_Report ("record aggregate",
                          Framework.Association (Contexts, Image (K_Record_Aggregate)));

               -- Record_Component_Associations + Record_Component_Choices/Component_Expression
               declare
                  Record_Associations : constant Asis.Association_List := Record_Component_Associations (Exp);
               begin
                  for Assoc in Record_Associations'Range loop
                     Check_Expression (Component_Expression (Record_Associations (Assoc)));
                  end loop;
               end;

            when An_Extension_Aggregate =>
               Do_Report ("record extension",
                          Framework.Association (Contexts, Image (K_Record_Aggregate)));

               -- Extension_Aggregate_Expression
               -- Record_Component_Associations + Record_Component_Choices/Component_Expression
               Check_Expression (Extension_Aggregate_Expression (Exp));
               declare
                  Record_Associations : constant Asis.Association_List :=
                    Record_Component_Associations (Exp);
               begin
                  for Assoc in Record_Associations'Range loop
                     Check_Expression (Component_Expression (Record_Associations (Assoc)));
                  end loop;
               end;

            when A_Positional_Array_Aggregate
              | A_Named_Array_Aggregate
              =>
               Do_Report ("array aggregate",
                          Framework.Association (Contexts, Image (K_Array_Aggregate)));

               -- Array_Component_Associations + Array_Component_Choices/Component_Expression
               declare
                  Array_Associations : constant Asis.Association_List :=
                    Array_Component_Associations (Exp);
               begin
                  for Assoc in Array_Associations'Range loop
                     declare
                        Choices : constant Asis.Element_List :=
                          Array_Component_Choices (Array_Associations (Assoc));
                        Choice : Asis.Element;
                     begin
                        for Choice_Index in Choices'Range loop
                           Choice := Choices (Choice_Index);
                           if not Is_Nil (Choice) then
                              case Element_Kind (Choice) is
                                 when An_Expression =>
                                    Check_Expression (Choice);
                                 when A_Definition =>
                                    case Definition_Kind (Choice) is
                                       when An_Others_Choice =>
                                          null;
                                       when A_Discrete_Range =>
                                          case Discrete_Range_Kind (Choice) is
                                             when Not_A_Discrete_Range =>
                                                Failure (Rule_Id & ": Array_Aggregate . Discrete_Range_Kind");
                                             when A_Discrete_Subtype_Indication
                                               | A_Discrete_Range_Attribute_Reference
                                               =>
                                                null;
                                             when A_Discrete_Simple_Expression_Range =>
                                                Check_Expression (Lower_Bound (Choice));
                                                Check_Expression (Upper_Bound (Choice));
                                          end case;
                                       when others =>
                                          Failure (Rule_Id & ": Array_Aggregate . Definition_Kind");
                                    end case;
                                 when others =>
                                    Failure (Rule_Id & ": Array_Aggregate . Element_Kind");
                              end case;
                           end if;
                        end loop;
                     end;
                     Check_Expression (Component_Expression (Array_Associations (Assoc)));
                  end loop;
               end;

            when An_In_Range_Membership_Test
              | A_Not_In_Range_Membership_Test
              =>
               Do_Report ("membership test",
                          Framework.Association (Contexts, Image (K_Logical_Operator)),
                          Loc => Get_Next_Word_Location (Membership_Test_Expression (Exp)));

               -- Check both tested expression and range
               Check_Expression (Membership_Test_Expression (Exp));
               declare
                  The_Range : constant Asis.Range_Constraint := Membership_Test_Range (Exp);
               begin
                  case Constraint_Kind (The_Range) is
                     when A_Range_Attribute_Reference =>
                        null;
                     when A_Simple_Expression_Range =>
                        Check_Expression (Lower_Bound (The_Range));
                        Check_Expression (Upper_Bound (The_Range));
                     when others =>
                        Failure (Rule_Id & ": Membership_Test_Range => invalid Constraint_Kind");
                  end case;
               end;

            when An_In_Type_Membership_Test
              | A_Not_In_Type_Membership_Test
              =>
               Do_Report ("membership test",
                          Framework.Association (Contexts, Image (K_Logical_Operator)));

               -- Check membership test expression
               Check_Expression (Membership_Test_Expression (Exp));

            when An_Indexed_Component =>
               Do_Report ("indexing",
                          Framework.Association (Contexts, Image (K_Indexing)));

               -- Check for implicit dereference
               if Is_Access_Expression (Prefix (Exp)) then
                Do_Report ("dereference",
                           Framework.Association (Contexts, Image (K_Dereference)));
               end if;
               -- Check both prefix and indexes of the component
               Check_Expression (Prefix (Exp));
               declare
                  Indexes : constant Asis.Expression_List := Index_Expressions (Exp);
               begin
                  for I in Indexes'Range loop
                     Check_Expression (Indexes (I));
                  end loop;
               end;

            when A_Slice =>
               Do_Report ("slice",
                          Framework.Association (Contexts, Image (K_Indexing)));

                -- Check for implicit dereference
               if Is_Access_Expression (Prefix (Exp)) then
                Do_Report ("dereference",
                           Framework.Association (Contexts, Image (K_Dereference)));
               end if;                                          -- Check both slice prefix and range
               Check_Expression (Prefix (Exp));
               declare
                  The_Range : constant Asis.Discrete_Range := Slice_Range (Exp);
               begin
                  case Discrete_Range_Kind (The_Range) is
                     when Not_A_Discrete_Range =>
                        Failure (Rule_Id & ": Slice_Range => Not_A_Discrete_Range");
                     when A_Discrete_Subtype_Indication
                       | A_Discrete_Range_Attribute_Reference
                       =>
                        null;
                     when A_Discrete_Simple_Expression_Range =>
                        Check_Expression (Lower_Bound (The_Range));
                        Check_Expression (Upper_Bound (The_Range));
                  end case;
               end;

            when A_Selected_Component =>
               -- Check for implicit dereference
               if Is_Access_Expression (Prefix (Exp)) then
                Do_Report ("dereference",
                           Framework.Association (Contexts, Image (K_Dereference)));
               end if;
               -- Check both prefix and selector
               Check_Expression (Prefix (Exp));
               Check_Expression (Selector (Exp));

            when A_Function_Call =>
               -- Check for implicit dereference
               if Is_Access_Expression (Prefix (Exp)) then
                Do_Report ("dereference",
                           Framework.Association (Contexts, Image (K_Dereference)));
               end if;
               -- Check prefix
               Check_Expression (Prefix (Exp));
               -- Check each parameter
               declare
                  Parameters : constant Asis.Association_List := Function_Call_Parameters (Exp);
               begin
                  for Index in Parameters'Range loop
                     Check_Expression (Actual_Parameter (Parameters (Index)));
                  end loop;
               end;

            when An_Explicit_Dereference =>
               Do_Report ("dereference",
                          Framework.Association (Contexts, Image (K_Dereference)));
               Check_Expression (Prefix (Exp));

            when A_Type_Conversion
              | A_Qualified_Expression
              =>
               Do_Report ("conversion or qualified expression",
                          Framework.Association (Contexts, Image (K_Conversion)));
               Check_Expression (Converted_Or_Qualified_Expression (Exp));

            when An_Allocation_From_Subtype =>
               Do_Report ("allocation",
                          Framework.Association (Contexts, Image (K_Allocation)));

            when An_Allocation_From_Qualified_Expression =>
               Do_Report ("allocation",
                          Framework.Association (Contexts, Image (K_Allocation)));
               Check_Expression (Allocator_Qualified_Expression (Exp));
         end case;
      end Check_Expression;


   begin -- Process_Entry_Declaration
      if Rule_Used = (Control_Kinds => False) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Check_Expression (Entry_Barrier (Decl));
   end Process_Entry_Declaration;

begin  -- Rules.Barrier_Expressions
   Framework.Rules_Manager.Register (Rule_Id,
                                     Rules_Manager.Semantic,
                                     Help_CB        => Help'Access,
                                     Add_Control_CB => Add_Control'Access,
                                     Command_CB     => Command'Access);
end Rules.Barrier_Expressions;
