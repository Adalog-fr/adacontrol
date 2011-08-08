----------------------------------------------------------------------
--  Rules.Simplifiable_Expressions - Package body                   --
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

-- Adactl
with
  Framework.Language,
  Framework.Rules_Manager,
  Framework.Reports;
pragma Elaborate (Framework.Language);

package body Rules.Simplifiable_expressions is
   use Framework, Ada.Strings.Wide_Unbounded;

   type Keywords is (K_Range,  K_Logical_True, K_Logical_False, K_Logical_Not, K_Parentheses,
                     K_Conversion, K_Logical);
   subtype Subrules is Keywords range Keywords'First .. Keywords'Pred (K_Logical);

   package Subrules_Flags_Utilities is new Framework.Language.Flag_Utilities (Keywords, "K_");
   use Subrules_Flags_Utilities;

   type Usage_Entry is
      record
         Used  : Boolean := False;
         Label : Unbounded_Wide_String;
      end record;
   type Usages is array (Subrules) of Usage_Entry;

   Ctl_Contexts : array (Control_Kinds) of Usages;
   Rule_Used    : Boolean := False;
   Save_Used    : Boolean;

   ----------
   -- Help --
   ----------

   procedure Help is
      use Utilities;
   begin
      User_Message  ("Rule: " & Rule_Id);
      Help_On_Flags (Header => "Parameter(s):", Footer => "(optional, default=all)");
      User_Message  ("Control occurrence of various forms of expressions that could be made simpler:");
      User_Message  ("  T'FIRST .. T'LAST that can be replaced by T'RANGE or T.");
      User_Message  ("  <expression> = (/=) True/False");
      User_Message  ("  not <comparison>");
      User_Message  ("  Unnecessary parentheses");
      User_Message  ("  Conversions to the expression's subtype");
   end Help;

   -----------------
   -- Add_Control --
   -----------------

   procedure Add_Control (Ctl_Label : in Wide_String; Ctl_Kind : in Control_Kinds) is
      use Framework.Language;
      Key : Keywords;

      procedure Add_Check (Subrule : Subrules) is
         use Utilities;
      begin
         if Ctl_Contexts (Ctl_Kind)(Subrule).Used then
            Parameter_Error (Rule_Id, "check already given: " & Image (Subrule, Lower_Case));
         else
            Ctl_Contexts (Ctl_Kind)(Subrule) := (Used => True, Label => To_Unbounded_Wide_String (Ctl_Label));
         end if;
      end Add_Check;

   begin  -- Add_Control
      if Parameter_Exists then
         while Parameter_Exists loop
            Key := Get_Flag_Parameter (Allow_Any => False);
            if Key = K_Logical then
               Add_Check (K_Logical_True);
               Add_Check (K_Logical_False);
               Add_Check (K_Logical_Not);
            else
               Add_Check (Key);
            end if;
         end loop;
      else
         Add_Check (K_Range);
         Add_Check (K_Logical_True);
         Add_Check (K_Logical_False);
         Add_Check (K_Logical_Not);
         Add_Check (K_Parentheses);
         Add_Check (K_Conversion);
      end if;
      Rule_Used  := True;
   end Add_Control;

   -------------
   -- Command --
   -------------

   procedure Command (Action : Framework.Rules_Manager.Rule_Action) is
      use Framework.Rules_Manager;
   begin
      case Action is
         when Clear =>
            --The following aggregate hangs Gnat, but the explicit loop is OK...
            --Context   := (others => (others => (Used => False, Label => Null_Unbounded_Wide_String)));
            for I in Ctl_Contexts'Range loop
               for J in Usages'Range loop
                  Ctl_Contexts (I)(J) := (Used => False, Label => Null_Unbounded_Wide_String);
               end loop;
            end loop;
            Rule_Used := False;
         when Suspend =>
            Save_Used := Rule_Used;
            Rule_Used := False;
         when Resume =>
            Rule_Used := Save_Used;
     end case;
   end Command;

   ------------------
   -- Process_Call --
   ------------------

   procedure Process_Call (Call : in Asis.Expression) is
      use Asis, Asis.Elements, Asis.Expressions, Framework.Reports;
      use Thick_Queries;

      subtype A_Comparison_Operator is Operator_Kinds range An_Equal_Operator .. A_Greater_Than_Or_Equal_Operator;

      type Param_Kind is (Static_True, Static_False, Expr);
      function "+" (Left : Wide_String) return Unbounded_Wide_String renames To_Unbounded_Wide_String;

      -- Message_Table (Operator, Left, Right)
      Message_Table : constant array (Operator_Kinds range An_Equal_Operator .. A_Not_Equal_Operator,
                                      Param_Kind,
                                      Param_Kind) of Unbounded_Wide_String
        := (An_Equal_Operator =>
              (Static_True =>
                 (Static_True  => +"Simplify expression: statically True",                    -- True = True
                  Static_False => +"Simplify expression: statically False",                   -- True = False
                  Expr         => +"Simplify expression 'True = <expr>' to just '<expr>'"),   -- True = <Expr>
               Static_False =>
                 (Static_True  => +"Simplify expression: statically False",                   -- False = True
                  Static_False => +"Simplify expression: statically True",                    -- False = False
                  Expr         => +"Simplify expression 'False = <expr>' to 'not <expr>'"),   -- False = <Expr>
               Expr =>
                 (Static_True  => +"Simplify expression '<expr> = True' to just '<expr>'",    -- <Expr>  = True
                  Static_False => +"Simplify expression '<expr> = False' to 'not <expr>'",    -- <Expr> = False
                  Expr         => +"")),                                                      -- <Expr> = <Expr>
            A_Not_Equal_Operator =>
              (Static_True =>
                 (Static_True  => +"Simplify expression: statically False",                   -- True /= True
                  Static_False => +"Simplify expression: statically True",                    -- True /= False
                  Expr         => + "Simplify expression 'True /= <expr>' to 'not <expr>'"),  -- True /= <Expr>
               Static_False =>
                 (Static_True  => +"Simplify expression: statically True",                    -- False /= True
                  Static_False => +"Simplify expression: statically False",                   -- False /= False
                  Expr         => +"Simplify expression 'False /= <expr>' to just '<expr>'"), -- False /= <Expr>
               Expr =>
                 (Static_True  => +"Simplify expression '<expr> /= True' to 'not <expr>'",    -- <Expr> /= True
                  Static_False => +"Simplify expression '<expr> /= False' to just '<expr>'",  -- <Expr> /= False
                  Expr         => +"")));                                                     -- <Expr> /= <Expr>

      function Get_Kind (Param : Asis.Expression) return Param_Kind is
         use Utilities;
         Good_Param : Asis.Expression := Param;
      begin
         while Expression_Kind (Good_Param) = A_Parenthesized_Expression loop
            Good_Param := Expression_Parenthesized (Good_Param);
         end loop;
         if Expression_Kind (Good_Param) = An_Enumeration_Literal
           and then To_Upper (Full_Name_Image (Good_Param)) = "STANDARD.FALSE"
         then
            return Static_False;
         elsif Expression_Kind (Good_Param) = An_Enumeration_Literal
           and then To_Upper (Full_Name_Image (Good_Param)) = "STANDARD.TRUE"
         then
            return Static_True;
         else
            return Expr;
         end if;
      end Get_Kind;

   begin  -- Process_Call
      if not Rule_Used then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      declare
         Op : constant Asis.Operator_Kinds := Operator_Kind (Called_Simple_Name (Call));
      begin
         case Op is
            when An_Equal_Operator .. A_Not_Equal_Operator =>
               declare
                  P : constant Asis.Association_List := Function_Call_Parameters (Call);
                  L : constant Param_Kind := Get_Kind (Actual_Parameter (P (1)));
                  R : constant Param_Kind := Get_Kind (Actual_Parameter (P (2)));
               begin
                  if Message_Table (Op, L, R) /= Null_Unbounded_Wide_String then
                     -- Report the highest priority from Check/Search
                     if Ctl_Contexts (Check) (K_Logical_False).Used
                       and then (L = Static_False or R = Static_False)
                     then
                        Report (Rule_Id,
                                To_Wide_String (Ctl_Contexts (Check) (K_Logical_False).Label),
                                Check,
                                Get_Location (Call),
                                To_Wide_String (Message_Table (Op, L, R)));
                     elsif Ctl_Contexts (Check) (K_Logical_True).Used and then (L = Static_True or R = Static_True) then
                        Report (Rule_Id,
                                To_Wide_String (Ctl_Contexts (Check) (K_Logical_True).Label),
                                Check,
                                Get_Location (Call),
                                To_Wide_String (Message_Table (Op, L, R)));
                     elsif Ctl_Contexts (Search) (K_Logical_False).Used
                       and then (L = Static_False or R = Static_False)
                     then
                        Report (Rule_Id,
                                To_Wide_String (Ctl_Contexts (Search) (K_Logical_False).Label),
                                Search,
                                Get_Location (Call),
                                To_Wide_String (Message_Table (Op, L, R)));
                     elsif Ctl_Contexts (Search) (K_Logical_True).Used
                       and then (L = Static_True or R = Static_True)
                     then
                        Report (Rule_Id,
                                To_Wide_String (Ctl_Contexts (Search) (K_Logical_True).Label),
                                Search,
                                Get_Location (Call),
                                To_Wide_String (Message_Table (Op, L, R)));
                     end if;

                     -- Always report Count
                     if Ctl_Contexts (Count) (K_Logical_False).Used and then (L = Static_False or R = Static_False) then
                        Report (Rule_Id,
                                To_Wide_String (Ctl_Contexts (Count) (K_Logical_False).Label),
                                Count,
                                Get_Location (Call),
                                To_Wide_String (Message_Table (Op, L, R)));
                     elsif Ctl_Contexts (Count) (K_Logical_True).Used and then (L = Static_True or R = Static_True) then
                        Report (Rule_Id,
                                To_Wide_String (Ctl_Contexts (Count) (K_Logical_True).Label),
                                Count,
                                Get_Location (Call),
                                To_Wide_String (Message_Table (Op, L, R)));
                     end if;
                  end if;
               end;
            when A_Not_Operator =>
               declare
                  P : constant Asis.Association_List := Function_Call_Parameters (Call);
                  L : Asis.Expression := Actual_Parameter (P (1));
                  Name : Asis.Expression;
               begin
                  while Expression_Kind (L) = A_Parenthesized_Expression loop
                     L := Expression_Parenthesized (L);
                  end loop;
                  if Expression_Kind (L) = A_Function_Call then
                     Name := Called_Simple_Name (L);
                     if Operator_Kind (Name) in A_Comparison_Operator then
                        if Ctl_Contexts (Check) (K_Logical_not).Used then
                           Report (Rule_Id,
                                   To_Wide_String (Ctl_Contexts (Check) (K_Logical_Not).Label),
                                   Check,
                                   Get_Location (Call),
                                   """not"" on comparison");
                        elsif Ctl_Contexts (Search) (K_Logical_not).Used then
                           Report (Rule_Id,
                                   To_Wide_String (Ctl_Contexts (Search) (K_Logical_Not).Label),
                                   Search,
                                   Get_Location (Call),
                                   """not"" on comparison");
                        end if;

                        -- Always report count
                        if Ctl_Contexts (Count) (K_Logical_not).Used then
                           Report (Rule_Id,
                                   To_Wide_String (Ctl_Contexts (Count) (K_Logical_Not).Label),
                                   Count,
                                   Get_Location (Call),
                                   """not"" on comparison");
                        end if;
                     end if;
                  end if;
               end;

            when others =>
               null;
         end case;
      end;
   end Process_Call;

   -------------------
   -- Process_Range --
   -------------------

   procedure Process_Range (Definition : in Asis.Definition) is
      use Asis, Asis.Declarations, Asis.Definitions,
        Asis.Elements, Asis.Expressions, Thick_Queries, Utilities;

      procedure Do_Reports (Message : Wide_String) is
         use Framework.Reports;
      begin
         if Ctl_Contexts (Check)(K_Range).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Check)(K_Range).Label),
                    Check,
                    Get_Location (Definition),
                    Message);
         elsif Ctl_Contexts (Search)(K_Range).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Search)(K_Range).Label),
                    Search,
                    Get_Location (Definition),
                    Message);
         end if;

         if Ctl_Contexts (Count)(K_Range).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Count)(K_Range).Label),
                    Count,
                    Get_Location (Definition),
                    Message);
         end if;
      end Do_Reports;

   begin  -- Process_Range
      if not Rule_Used then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      case Discrete_Range_Kind (Definition) is
         when A_Discrete_Simple_Expression_Range =>
            declare
               LB : constant Expression := Lower_Bound (Definition);
               UB : constant Expression := Upper_Bound (Definition);
            begin
               if A4G_Bugs.Attribute_Kind (LB) /= A_First_Attribute
                 or A4G_Bugs.Attribute_Kind (UB) /= A_Last_Attribute
               then
                  return;
               end if;

               -- Must deal with the following cases when determining 'T':-
               -- 1) T'FIRST
               -- 2) T'BASE'FIRST
               -- 3) T (A)'FIRST
               -- 4) T'FIRST (B)
               -- We must also not fall into the trap of recommending
               -- T'BASE'FIRST .. T'LAST or T'FIRST (X) .. T'LAST (Y) for simplification.
               declare
                  -- First we remove the 'FIRST and 'LAST attributes.
                  LP  : Asis.Expression := Prefix (LB);
                  UP  : Asis.Expression := Prefix (UB);
                  ALB : constant Expression_List := Attribute_Designator_Expressions (LB);
                  AUB : constant Expression_List := Attribute_Designator_Expressions (UB);
               begin
                  -- Both the first and last attributes must have either no attribute designators expressions
                  -- or else have the same value.
                  -- Take the Wide_Value below for the case of the naughty user who wrote something like
                  ---Tab'First (10#1#) .. Tab'Last (1).
                  -- Note that attribute designator expressions can only ever have a length of 0 or 1,
                  --      and are satic integers.
                  if ALB'Length /= AUB'Length
                    or else (ALB'Length = 1  -- Implies AUB'LENGTH = 1
                             and then Discrete_Static_Expression_Value (ALB (1)) /=
                               Discrete_Static_Expression_Value (AUB (1)))
                  then
                     return;
                  end if;

                  -- Remove the 'BASE attribute but only if it is applied to both attributes.
                  if Expression_Kind (LP) = An_Attribute_Reference then
                     if Expression_Kind (UP) /= An_Attribute_Reference  then
                        return;
                     end if;
                     LP := Prefix (LP);
                     UP := Prefix (UP);
                  elsif Expression_Kind (UP) = An_Attribute_Reference then
                     return;
                  end if;

                  -- Remove indexings and selectors for record elements.
                  -- If in doubt, give up.
                  loop
                     case Expression_Kind (LP) is
                        when An_Identifier =>
                           exit;

                        when A_Selected_Component =>
                           case Declaration_Kind (A4G_Bugs.Corresponding_Name_Declaration (Selector (LP))) is
                              when A_Component_Declaration | A_Discriminant_Specification =>
                                 if Expression_Kind (UP) /= A_Selected_Component then
                                    return;
                                 end if;

                                 -- It's a record field, a protected type field...
                                 if not Is_Equal (A4G_Bugs.Corresponding_Name_Declaration (Selector (LP)),
                                                  A4G_Bugs.Corresponding_Name_Declaration (Selector (UP)))
                                 then
                                    return;
                                 end if;
                                 LP := Prefix (LP);
                                 UP := Prefix (UP);
                              when A_Variable_Declaration
                                | A_Constant_Declaration
                                | An_Object_Renaming_Declaration
                                | A_Subtype_Declaration
                                | An_Ordinary_Type_Declaration
                                =>
                                 -- Its a Pack.Var or Pack.T selector
                                 exit;
                              when others =>
                                 Failure ("Wrong selected component",
                                          A4G_Bugs.Corresponding_Name_Declaration (Selector (LP)));
                           end case;

                        when An_Indexed_Component =>
                           if Expression_Kind (UP) /= An_Indexed_Component then
                              return;
                           end if;

                           -- Check that the indexing expressions are statically the same.
                           -- We currently recognize as identical indexing expressions that are:
                           --   - Integer litterals
                           --   - Enumeration litterals
                           --   - Identical constants and loop control parameters
                           declare
                              L_Indexers : constant Asis.Expression_List := Index_Expressions (LP);
                              U_Indexers : constant Asis.Expression_List := Index_Expressions (UP);
                           begin
                              if L_Indexers'Length /= U_Indexers'Length then
                                 return;
                              end if;
                              for I in L_Indexers'Range loop
                                 if Expression_Kind (L_Indexers (I)) /= Expression_Kind (U_Indexers (I)) then
                                    return;
                                 end if;

                                 case Expression_Kind (L_Indexers (I)) is
                                    when An_Integer_Literal =>
                                       if ASIS_Integer'Wide_Value (Value_Image (L_Indexers (I)))
                                         /= ASIS_Integer'Wide_Value (Value_Image (U_Indexers (I)))
                                       then
                                          return;
                                       end if;
                                    when An_Enumeration_Literal =>
                                       if To_Upper (Value_Image (L_Indexers (I)))
                                         /= To_Upper (Value_Image (U_Indexers (I)))
                                       then
                                          return;
                                       end if;
                                    when An_Identifier =>
                                       case Declaration_Kind (A4G_Bugs.Corresponding_Name_Declaration (L_Indexers (I)))
                                       is
                                          when A_Constant_Declaration
                                            | A_Deferred_Constant_Declaration
                                            | A_Loop_Parameter_Specification
                                            =>
                                             if not Is_Equal (Corresponding_Name_Definition (L_Indexers (I)),
                                                              Corresponding_Name_Definition (U_Indexers (I)))
                                             then
                                                return;
                                             end if;
                                          when others =>
                                             return;
                                       end case;
                                    when others =>
                                       return;
                                 end case;
                              end loop;
                           end;

                           -- Here, both indexings are the same
                           LP := Prefix (LP);
                           UP := Prefix (UP);

                        when A_Function_Call | An_Explicit_Dereference =>
                           -- Certainly not static
                           return;

                        when others =>
                          Failure ("Unexpected expression kind", LP);
                     end case;

                  end loop;

                  -- If we still have a selected name, the prefixes are packages
                  -- => Get rid of them
                  -- To be honnest: maybe not for UP, but then it will fail later
                  if Expression_Kind (LP) = A_Selected_Component then
                     LP := Selector (LP);
                  end if;
                  if Expression_Kind (UP) = A_Selected_Component then
                     UP := Selector (UP);
                  end if;

                  -- Here we have a "clean" name for lower/upper prefix
                  -- Check the full expanded names of both bounds.
                  if Full_Name_Image (LP) = Full_Name_Image (UP) then
                     case Declaration_Kind (A4G_Bugs.Corresponding_Name_Declaration (LP)) is
                        when A_Subtype_Declaration
                          | An_Ordinary_Type_Declaration
                          | A_Formal_Type_Declaration
                          =>
                           Do_Reports ("(T)'First .. (T)'Last replaceable with (sub)type(T)");
                        when A_Variable_Declaration
                          | A_Constant_Declaration
                          | An_Object_Renaming_Declaration
                          | A_Deferred_Constant_Declaration
                          | A_Formal_Object_Declaration
                          | A_Parameter_Specification
                          | A_Component_Declaration
                          =>
                           Do_Reports ("(T)'First .. (T)'Last replaceable with (T)'Range");
                        when others =>
                           Failure ("Unexpected Element_Kind 1: " &
                                    Declaration_Kinds'Wide_Image (Declaration_Kind
                                                                  (A4G_Bugs.Corresponding_Name_Declaration
                                                                   (LP))));
                     end case;
                  end if;
               end;
            end;

         when A_Discrete_Range_Attribute_Reference =>
            -- We are interested only in the case where the prefix is a (sub)type
            declare
               P    : Asis.Expression := Prefix (Range_Attribute (Definition));
               Decl : Asis.Declaration;
               Def  : Asis.Definition;
            begin
               case Expression_Kind (P) is
                  when An_Identifier =>
                     null;
                  when A_Selected_Component =>
                     -- Could be Pack.T
                     P := Selector (P);
                  when others =>
                     -- Prefix cannot denote a (sub)type
                     return;
               end case;

               -- Get rid of subtypes, incomplete views...
               Decl := A4G_Bugs.Corresponding_Name_Declaration (P);
               if Declaration_Kind (Decl) = A_Subtype_Declaration then
                  Decl := Corresponding_First_Subtype (Decl);
               end if;

               if Declaration_Kind (Decl) = A_Private_Type_Declaration
                 or Declaration_Kind (Decl) = An_Incomplete_Type_Declaration
               then
                  Decl := Corresponding_Type_Declaration (Decl);
               end if;

               case Declaration_Kind (Decl) is
                  when An_Ordinary_Type_Declaration
                    | A_Formal_Type_Declaration
                    =>
                     -- Get rid of derived types, including formal derived type
                     -- We can of course have a type derived from a formal derived type,
                     -- and conversely. To any depth.
                     Def := Type_Declaration_View (Decl);
                     loop
                        if Type_Kind (Def) in A_Derived_Type_Definition .. A_Derived_Record_Extension_Definition then
                           Def := Type_Declaration_View (A4G_Bugs.Corresponding_Root_Type (Def));
                        elsif Formal_Type_Kind (Def) = A_Formal_Derived_Type_Definition then
                           Def := Type_Declaration_View (Corresponding_First_Subtype
                                                         (A4G_Bugs.Corresponding_Name_Declaration
                                                          (Subtype_Simple_Name (Def))));
                        else
                           exit;
                        end if;
                     end loop;

                     case Type_Kind (Def) is
                        when An_Enumeration_Type_Definition
                          | A_Signed_Integer_Type_Definition
                          | A_Modular_Type_Definition
                          | A_Floating_Point_Definition
                          | An_Ordinary_Fixed_Point_Definition
                          | A_Decimal_Fixed_Point_Definition
                          =>
                           Do_Reports ("(T)'RANGE replaceable with (sub)type(T)");
                        when An_Unconstrained_Array_Definition
                          | A_Constrained_Array_Definition
                          =>
                           null;
                        when Not_A_Type_Definition =>
                           -- Can  be a formal type here
                           case Formal_Type_Kind (Def) is
                              when A_Formal_Discrete_Type_Definition
                                | A_Formal_Signed_Integer_Type_Definition
                                | A_Formal_Modular_Type_Definition
                                | A_Formal_Floating_Point_Definition
                                | A_Formal_Ordinary_Fixed_Point_Definition
                                | A_Formal_Decimal_Fixed_Point_Definition
                                =>
                                 Do_Reports ("(T)'RANGE replaceable with (sub)type(T)");
                              when A_Formal_Unconstrained_Array_Definition
                                | A_Formal_Constrained_Array_Definition
                                =>
                                 null;
                              when others =>
                                 Failure ("Unexpected formal type kind: "
                                          & Formal_Type_Kinds'Wide_Image(Formal_Type_Kind (Def)), P);
                           end case;

                        when others =>
                           Failure ("Unexpected type kind: " & Type_Kinds'Wide_Image(Type_Kind (Def)), P);
                     end case;

                  when A_Variable_Declaration
                    | A_Constant_Declaration
                    | A_Deferred_Constant_Declaration
                    | A_Formal_Object_Declaration
                    | A_Parameter_Specification
                    | A_Component_Declaration
                    | An_Object_Renaming_Declaration
                    =>
                     null;

                  when others =>
                     Failure ("Unexpected Element_Kind 2: " &
                              Declaration_Kinds'Wide_Image (Declaration_Kind (Decl)));
               end case;
            end;

         when A_Discrete_Subtype_Indication =>
            -- Nothing simplifiable here
            null;

         when Not_A_Discrete_Range =>
            Failure ("Not a discrete range");
      end case;
   end Process_Range;

   ---------------------------
   -- Process_Parenthesized --
   ---------------------------

   procedure Process_Parenthesized (Expr : in Asis.Expression) is
      use Asis, Asis.Elements, Asis.Expressions;

      procedure Do_Report is
         use Framework.Reports;
         Message : constant Wide_String := "Unnecessary parentheses in expression";
      begin
         if Ctl_Contexts (Check)(K_Parentheses).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Check)(K_Parentheses).Label),
                    Check,
                    Get_Location (Expr),
                    Message);
         elsif Ctl_Contexts (Search)(K_Parentheses).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Search)(K_Parentheses).Label),
                    Search,
                    Get_Location (Expr),
                    Message);
         end if;

         if Ctl_Contexts (Count)(K_Parentheses).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Count)(K_Parentheses).Label),
                    Count,
                    Get_Location (Expr),
                    Message);
         end if;
      end Do_Report;

      type Priority_Level is (Logical, Relational, Adding, Multiplying, Highest, Primary);
      Priority : constant array (Asis.Operator_Kinds) of Priority_Level
        := (Not_An_Operator                                              => Primary,
            An_And_Operator          .. An_Xor_Operator                  => Logical,
            An_Equal_Operator        .. A_Greater_Than_Or_Equal_Operator => Relational,
            A_Plus_Operator          .. A_Unary_Minus_Operator           => Adding,
            A_Multiply_Operator      .. A_Rem_Operator                   => Multiplying,
            An_Exponentiate_Operator .. A_Not_Operator                   => Highest);

      Enclosing : Asis.Element;
      Enclosed  : Asis.Element;
   begin  -- Process_Parenthesized
      if not Rule_Used then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Enclosing := Enclosing_Element (Expr);
      if Element_Kind (Enclosing) = An_Association then
         Enclosing := Enclosing_Element (Enclosing);
      end if;

      case Expression_Kind (Enclosing) is
         when Not_An_Expression
           =>
            Do_Report;

         when A_Function_Call =>
            if Is_Prefix_Call (Enclosing) then
               Do_Report;
            else
               Enclosed := Expression_Parenthesized (Expr);
               case Expression_Kind (Enclosed) is
                  when A_Function_Call =>
                     if Is_Prefix_Call (Enclosed)
                       or else  Priority (Operator_Kind (Prefix (Enclosing)))
                              < Priority (Operator_Kind (Prefix (Enclosed)))
                     then
                        Do_Report;
                     end if;
                  when An_And_Then_Short_Circuit .. An_Or_Else_Short_Circuit =>
                     null;
                  when others =>
                     Do_Report;
               end case;
            end if;

         when An_And_Then_Short_Circuit
           | An_Or_Else_Short_Circuit
           =>
            Enclosed := Expression_Parenthesized (Expr);
            case Expression_Kind (Enclosed) is
               when An_And_Then_Short_Circuit .. An_Or_Else_Short_Circuit =>
                  if Expression_Kind (Enclosing) = Expression_Kind (Enclosed) then
                     Do_Report;
                     end if;
               when A_Function_Call =>
                  if Is_Prefix_Call (Enclosed) or else Priority (Operator_Kind (Prefix (Enclosed))) > Logical then
                     Do_Report;
                  end if;
               when others =>
                  Do_Report;
            end case;

         when others =>
            null;
      end case;

   end Process_Parenthesized;

   ------------------------
   -- Process_Conversion --
   ------------------------

   procedure Process_Conversion (Expr : in Asis.Expression) is
      use Asis, Asis.Declarations, Asis.Elements, Asis.Expressions;
      use Utilities;

      Source : Asis.Declaration;
      Target : Asis.Element;

      procedure Do_Report is
         use Framework.Reports;
      begin
         if Ctl_Contexts (Check) (K_Conversion).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Check) (K_Conversion).Label),
                    Check,
                    Get_Location (Expr),
                    "unnecessary conversion");
         elsif Ctl_Contexts (Search) (K_Conversion).Used  then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Search) (K_Conversion).Label),
                    Search,
                    Get_Location (Expr),
                    "unnecessary conversion");
         end if;

         -- Always report Count
         if Ctl_Contexts (Count) (K_Conversion).Used then
            Report (Rule_Id,
                    To_Wide_String (Ctl_Contexts (Count) (K_Conversion).Label),
                    Count,
                    Get_Location (Expr),
                    "");
         end if;
      end Do_Report;
   begin   -- Process_Conversion
      if not Rule_Used then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Source := A4G_Bugs.Corresponding_Expression_Type (Converted_Or_Qualified_Expression (Expr));
      if Is_Nil (Source) then
         -- The expression is of an anonymous or dynamic type
         -- certainly not suspicious
         return;
      end if;
      if Declaration_Kind (Source) = An_Incomplete_Type_Declaration then
         -- Use full declaration instead
         Source := Corresponding_Type_Declaration (Source);
      end if;

      Target := Converted_Or_Qualified_Subtype_Mark (Expr);
      case Expression_Kind (Target) is
         when A_Selected_Component =>
            Target := Selector (Target);
         when An_Attribute_Reference =>
            case A4G_Bugs.Attribute_Kind (Target) is
               when A_Base_Attribute =>
                  -- Never necessary
                  Do_Report;
                  return;
               when A_Class_Attribute =>
                  -- Since a class wide type has no declaration, it is hard
                  -- to check whether the source is class-wide
                  -- Just consider it is OK
                  return;
               when others =>
                  Failure ("Unexpected type attribute", Target);
            end case;
         when others =>
            null;
      end case;
      Target := A4G_Bugs.Corresponding_Name_Declaration (Target);
      if Is_Equal (Source, Target)
        or else Is_Equal (Corresponding_First_Subtype (Source), Target)
      then
         Do_Report;
      end if;
   end Process_Conversion;

begin  -- Rules.Simplifiable_expressions
   Framework.Rules_Manager.Register (Rule_Id,
                                     Rules_Manager.Semantic,
                                     Help_CB        => Help'Access,
                                     Add_Control_CB => Add_Control'Access,
                                     Command_CB     => Command'Access);
end Rules.Simplifiable_expressions;
