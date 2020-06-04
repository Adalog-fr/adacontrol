----------------------------------------------------------------------
--  Rules.Known_Exceptions - Package body                           --
--                                                                  --
--  This software  is (c) Adalog  2004-2020.                        --
--  The Ada Controller is  free software; you can  redistribute  it --
--  and/or modify it under  terms of the GNU General Public License --
--  as published by the Free Software Foundation; either version 2, --
--  or (at your option) any later version. This unit is distributed --
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
  Asis.Definitions,
  Asis.Elements,
  Asis.Exceptions,
  Asis.Expressions;

-- Adalog
with
  Thick_Queries,
  Utilities;

-- Adactl
with
  Framework.Language,
  Framework.Locations,
  Framework.Object_Tracker,
  Framework.Rules_Manager,
  Framework.Reports;
pragma Elaborate (Framework.Language);

package body Rules.Known_Exceptions is
   use Framework, Framework.Control_Manager;

   type Subrules is (SR_Index, SR_Discriminant, SR_Access);
   package Subrules_Flag_Utilities is new Framework.Language.Flag_Utilities (Subrules, "SR_");

   type Usage_Flags is array (Subrules) of Boolean;
   No_Rule_Used : constant Usage_Flags := (others => False);

   Rule_Used : Usage_Flags := No_Rule_Used;
   Save_Used : Usage_Flags;

   Contexts : array (Subrules) of Basic_Rule_Context;

   ----------
   -- Help --
   ----------

   procedure Help is
      use Subrules_Flag_Utilities, Utilities;
   begin
      User_Message ("Rule: " & Rule_Id);
      User_Message ("Control constructs that are provably always raising an exception");
      User_Message;
      Help_On_Flags (Header => "Parameter(s):", Footer => "(optional, default=all)");
   end Help;

   -----------------
   -- Add_Control --
   -----------------

   procedure Add_Control (Ctl_Label : in Wide_String; Ctl_Kind : in Control_Kinds) is
      use Framework.Language, Subrules_Flag_Utilities;

      procedure Add_Or_Merge (Sr : Subrules) is
         use Utilities;
      begin
         if Rule_Used (Sr) then
            if not Basic.Merge_Context (Contexts (Sr), Ctl_Kind, Ctl_Label) then
               Parameter_Error (Rule_Id, "rule already specified for " & Image (Sr, Lower_Case));
            end if;
         else
            Contexts  (Sr) := Basic.New_Context (Ctl_Kind, Ctl_Label);
            Rule_Used (Sr) := True;
         end if;
      end Add_Or_Merge;
   begin -- Add_Control
      if Parameter_Exists then
         while Parameter_Exists loop
            Add_Or_Merge (Get_Flag_Parameter (Allow_Any => False));
         end loop;
      else
         for S in Subrules loop
            Add_Or_Merge (S);
         end loop;
      end if;
   end Add_Control;

   -------------
   -- Command --
   -------------

   procedure Command (Action : Framework.Rules_Manager.Rule_Action) is
      use Framework.Rules_Manager;
   begin
      case Action is
         when Clear =>
            Rule_Used := No_Rule_Used;
         when Suspend =>
            Save_Used := Rule_Used;
            Rule_Used := No_Rule_Used;
         when Resume =>
            Rule_Used := Save_Used;
      end case;
   end Command;

   -------------------------
   -- Process_Dereference --
   -------------------------

   procedure Process_Dereference (Expr : Asis.Expression) is
   -- Pre: the Prefix of expr is an access object
   -- Works with an explicit dereference, but also an indexed component
   -- or a selected component when the prefix is an implicit dereference
      use Asis, Asis.Elements, Asis.Expressions;
      use Framework.Locations, Framework.Reports, Thick_Queries;
   begin
      if not Rule_Used (SR_Access) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      if Discrete_Static_Expression_Value (Prefix (Expr)) = 0 then  -- null
         Report (Rule_Id, Contexts (SR_Access), Get_Location (Expr),
                 (if Expression_Kind (Expr) = An_Explicit_Dereference then "Explicit" else "Implicit")
                  & " dereference raises Constraint_Error (null pointer)");
      end if;
   end Process_Dereference;

   ------------------------------
   -- Process_Index_Expression --
   ------------------------------

   procedure Process_Index_Expression (Expr : Asis.Expression) is
      use Asis.Expressions;
      use Framework.Locations, Framework.Reports, Thick_Queries;
   begin
      if Is_Access_Expression (Prefix (Expr)) then
         -- Implicit dereference
         Process_Dereference (Expr);
      end if;

      if not Rule_Used (SR_Index) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      declare
         Bounds    : constant Extended_Biggest_Int_List := Discrete_Constraining_Values (Prefix (Expr),
                                                                                         Follow_Access => True);
         Bound_Inx :          Asis.List_Index           := Bounds'First;
         Indexes   : constant Asis.Expression_List      := Index_Expressions (Expr);
         Inx_Val   :          Extended_Biggest_Int;
      begin
         if Bounds = Nil_Extended_Biggest_Int_List then
            -- Not a true indexing (user defined)
            return;
         end if;

         for Var_Inx : Asis.Expression of Indexes loop
            Inx_Val := Discrete_Static_Expression_Value (Var_Inx, Minimum);
            if         Inx_Val                /= Not_Static
              and then Bounds (Bound_Inx + 1) /= Not_Static
              and then Inx_Val >  Bounds (Bound_Inx + 1)
            then
               Report (Rule_Id, Contexts (SR_Index), Get_Location (Var_Inx), "Indexing raises Constraint_Error");
            end if;
            Inx_Val := Discrete_Static_Expression_Value (Var_Inx, Maximum);
            if         Inx_Val            /= Not_Static
              and then Bounds (Bound_Inx) /= Not_Static
              and then Inx_Val <  Bounds (Bound_Inx)
            then
               Report (Rule_Id, Contexts (SR_Index), Get_Location (Var_Inx), "Indexing raises Constraint_Error");
            end if;
            Bound_Inx := Bound_Inx + 2;
         end loop;
      end;
   end Process_Index_Expression;

   --------------------------------
   -- Process_Selected_Component --
   --------------------------------

   procedure Process_Selected_Component (Expr : Asis.Expression) is
   -- It is not necessary to check all identifiers for the case of a renaming declaration whose target
   -- is a subcomponent, because the subcomponent will be analyzed by this procedure as part of the renaming
   -- declaration, and it is not allowed to rename a subcomponent of a mutable record.
      use Asis, Asis.Definitions, Asis.Elements, Asis.Expressions;
      use Framework.Locations, Framework.Object_Tracker, Framework.Reports, Thick_Queries, Utilities;

      function Discriminant_Value (Parent : Asis.Expression; Discr  : Asis.Expression) return Object_Value_Set is
      -- Returns the value of the discriminant Discr of Parent, following inherited discriminants
         Parent_Name : Asis.Expression;
         Parent_Decl : Asis.Declaration;
         Discr_Name  : Asis.Defining_Name;
         Discr_Value : Asis.Expression := Nil_Element;
         Var         : Asis.Expression;
         Def         : Asis.Definition;
      begin
         if Expression_Kind (Parent) in A_Function_Call | An_Indexed_Component then
            -- Too dynamic for us
            return Unknown_Value (Untracked);
         end if;
         Parent_Name := Ultimate_Name (Parent);
         Parent_Decl := Corresponding_Name_Declaration (Parent_Name);
         Discr_Name  := Corresponding_Name_Definition (Discr);

         -- Get rid of some trivial cases
         case Declaration_Kind (Parent_Decl) is
            when An_Object_Declaration | A_Parameter_Specification =>
               -- simple case: Object.Compo
               return Object_Value (Parent_Name, Discr_Name);
            when An_Element_Iterator_Specification =>
               -- too complicated for us...
               return Unknown_Value (Untracked);
            when others =>
               null;
         end case;

         if Is_Access_Subtype (Thick_Queries.Corresponding_Expression_Type_Definition (Parent_Name)) then
            -- Implicit dereference: we don't know
            return Unknown_Value (Untracked);
         end if;

         -- Find the constraint of the parent
         Def := Subtype_Constraint (Constraining_Definition (Parent_Decl));
         if Is_Nil (Def) then
            -- No constraint => The discriminant is mutable, no idea what it is
            return Unknown_Value (Untracked);
         end if;

         -- Here, the component declaration has its own constraint
         for Assoc : Asis.Association of Discriminant_Associations (Def, Normalized => True) loop
            if Is_Equal (Discriminant_Selector_Names (Assoc) (1), Discr_Name) then
               Discr_Value := Discriminant_Expression (Assoc);
               exit;
            end if;
         end loop;
         if Is_Nil (Discr_Value) then
            Failure ("Discriminant_Value: not found (2)", Discr);
         end if;

         -- Transmitted discriminants are always direct names
         -- This implies that if a name of a discriminant is the sole element of the constraint, it
         -- belongs necessarily to the enclosing structure (otherwise it would not be directly accessible)
         if Expression_Kind (Discr_Value) = An_Identifier
           and then Declaration_Kind (Corresponding_Name_Declaration (Discr_Value)) = A_Discriminant_Specification
         then -- A transmitted discriminant
            return Discriminant_Value (Prefix(Enclosing_Element (Parent_Name)), Discr_Value);
         else
            return Expression_Value (Discr_Value, RM_Static => True);
            -- We need RM_Static here, because the expression comes from the object declaration.
            -- If it involves variables, they may have changed since the object declaration was elaborated.
         end if;
      end Discriminant_Value;

      Current_Branch : Asis.Variant;
   begin  -- Process_Selected_Component
      if Is_Access_Expression (Prefix (Expr)) then
         -- Implicit dereference
         Process_Dereference (Expr);
      end if;

      if not Rule_Used (SR_Discriminant) then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      begin
         Current_Branch := Corresponding_Name_Declaration (Selector (Expr)); -- TBH: not yet a variant
      exception
         when Asis.Exceptions.ASIS_Inappropriate_Element =>
            -- Raised by Corresponding_Name_Declaration of predefined "special" identifiers, like the
            -- ones that are part of pragmas.
            -- Anyway, these have no value and are not tracked.
            return;
      end;
      if Declaration_Kind (Current_Branch) /= A_Component_Declaration then
         return;
      end if;

      Current_Branch := Enclosing_Element (Current_Branch);
      while Definition_Kind (Current_Branch) = A_Variant loop
         -- Component (or enclosing variang) is part of a variant

         declare
            Possible_Values : constant Asis.Element_List := Variant_Choices (Current_Branch);
            Discr_Value     : constant Object_Value_Set  := Discriminant_Value (Prefix (Expr),
                                                                                          Discriminant_Direct_Name
                                                                                           (Enclosing_Element
                                                                                            (Current_Branch)));
            Bounds          : Extended_Biggest_Int_List (1 .. 2);
            Possibly_Inside : Boolean := False;
         begin
            if Discr_Value.Kind = Untracked
              or else (Discr_Value.Imin = Not_Static or Discr_Value.Imax = Not_Static)
            then
               return;
            end if;

            On_Possible_Values :
            for Val : Asis.Element of Possible_Values loop
               case Element_Kind (Val) is
                  when An_Expression =>
                     Bounds (1) := Discrete_Static_Expression_Value (Val);
                     Bounds (2) := Bounds (1); --## Rule line off Assignments ## No aggregate, evaluate only once
                  when A_Definition =>   -- range or others
                     if Definition_Kind (Val) = An_Others_Choice then
                        Bounds := (Not_Static, Not_Static);
                     else
                        Bounds := Discrete_Constraining_Values (Val);
                     end if;
                  when others =>
                     Failure ("Process_Selected_Component: bad choice", Val);
               end case;
               if        Bounds (1)         = Not_Static   -- Bounds ARE static, but we may not
                 or else Bounds (2)         = Not_Static   -- be able to compute them
                 or else not (Discr_Value.Imin > Bounds (2) or Discr_Value.Imax < Bounds (1))
               then
                  Possibly_Inside := True;
                  exit On_Possible_Values;
               end if;
            end loop On_Possible_Values;

            if not Possibly_Inside then
               if Discr_Value.Imin = Discr_Value.Imax then
                  Report (Rule_Id, Contexts (SR_Discriminant), Get_Location (Selector (Expr)),
                          "Access to component raises Constraint_Error, discriminant "
                          & Name_Image (Discriminant_Direct_Name (Enclosing_Element (Current_Branch)))
                          & "= "
                          & Biggest_Int_Img (Discr_Value.Imin));
               else
                  Report (Rule_Id, Contexts (SR_Discriminant), Get_Location (Selector (Expr)),
                          "Access to component raises Constraint_Error, discriminant "
                          & Name_Image (Discriminant_Direct_Name (Enclosing_Element (Current_Branch)))
                          & " in "
                          & Biggest_Int_Img (Discr_Value.Imin)
                          & ".."
                          &  Biggest_Int_Img (Discr_Value.Imax));
               end if;
            end if;
         end;
         Current_Branch := Enclosing_Element (Enclosing_Element (Current_Branch));
      end loop;
   end Process_Selected_Component;


begin  -- Rules.Known_Exceptions
   Framework.Rules_Manager.Register (Rule_Id,
                                     Rules_Manager.Semantic,
                                     Help_CB        => Help'Access,
                                     Add_Control_CB => Add_Control'Access,
                                     Command_CB     => Command'Access);
end Rules.Known_Exceptions;
