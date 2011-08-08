----------------------------------------------------------------------
--  Rules.Side_Effect_Parameters - Package body                     --
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
  Asis.Declarations,
  Asis.Elements,
  Asis.Expressions,
  Asis.Iterator;

-- Adalog
with
  Thick_Queries,
  Utilities;

-- Adactl
with
  Framework.Language,
  Framework.Rules_Manager,
  Framework.Reports;

package body Rules.Side_Effect_Parameters is
   use Framework, Utilities;

   -- Algorithm:
   --
   -- For each subprogram call or generic instantiation, we traverse manually each of the
   -- actual parameters.
   --
   -- Each occurrence of a check/search command is given a unique Rule_ID number (hence limiting
   -- the number of check/search command that can be given - adjustable by setting the Max_Identical_Rules
   -- constant).
   --
   -- If during the traversal we encounter a call to a "bad function" from rule N, and slot N of the Called_By
   -- table is empty, we store in the slot the position number of the parameter that includes the call.
   -- If the slot is not empty, then there is a conflict, and the value of the slot gives the position of
   -- the conflicting element.
   --
   -- Note that we store only the first "bad function". This means that if there is a conflict between
   -- parameters 1, 2, and 3, we will output that "2 conflicts with 1" and that "3 conflicts with 1", but
   -- not that "2 conflicts with 3". That seems good enough.
   --
   -- The Called_Func table is similar to Called_By and holds a reference to the corresponding function for
   -- more precise error mesages.

   Rules_Used : Rule_Index := 0;
   Save_Used  : Rule_Index;

   type Entity_Context is new Basic_Rule_Context with
      record
         Rule_Id : Rule_Index;
      end record;

   Bad_Functions  : Context_Store;
   Called_By   : array (Rule_Index) of Asis.ASIS_Natural;
   Called_Func : array (Rule_Index) of Asis.Element;

   ----------
   -- Help --
   ----------

   procedure Help is
   begin
      User_Message ("Rule: " & Rule_Id);
      User_Message ("Parameter(s): <side effect function names>");
      User_Message ("Control subprogram calls or generic instantiations that call");
      User_Message ("functions with side effect and where the order of evaluation matters");
   end Help;

   -------------
   -- Add_Use --
   -------------

   procedure Add_Use (Label     : in Wide_String;
                      Rule_Type : in Rule_Types) is
      use Framework.Language;

      Entity : Entity_Specification;
   begin
      if not Parameter_Exists then
         Parameter_Error (Rule_Id, "missing function name");
      end if;

      if Rules_Used = Rule_Index'Last then
         Parameter_Error (Rule_Id,
                          "Rule cannot be specified more than" & Rule_Index'Wide_Image (Rule_Index'Last) & " times");
      end if;

      Rules_Used := Rules_Used + 1;

      while Parameter_Exists loop
         Entity := Get_Entity_Parameter;
         Associate (Bad_Functions,
                    Entity,
                    Entity_Context'(Basic.New_Context (Rule_Type, Label) with Rules_Used),
                    Additive => True);
      end loop;
   end Add_Use;

   -------------
   -- Command --
   -------------

   procedure Command (Action : Framework.Rules_Manager.Rule_Action) is
      use Framework.Rules_Manager;
   begin
      case Action is
         when Clear =>
            Rules_Used := 0;
            Clear (Bad_Functions);
         when Suspend =>
            Save_Used  := Rules_Used;
            Rules_Used := 0;
         when Resume =>
            Rules_Used := Save_Used;
      end case;
   end Command;

   -------------
   -- Prepare --
   -------------

   procedure Prepare is
   begin
      Balance (Bad_Functions);
   end Prepare;

   --------------
   -- Traverse --
   --------------

   type Association_Access is access constant Asis.Association_List;

   type State_Information is
     record
        Param_Pos : Asis.List_Index;
        Assoc     : Association_Access;
     end record;

   procedure Pre_Procedure (Element : in     Asis.Element;
                            Control : in out Asis.Traverse_Control;
                            State   : in out State_Information);

   procedure Post_Procedure (Element : in     Asis.Element;
                             Control : in out Asis.Traverse_Control;
                             State   : in out State_Information);

   procedure Traverse is new Asis.Iterator.Traverse_Element
     (State_Information, Pre_Procedure, Post_Procedure);

   -------------------
   -- Pre_Procedure --
   -------------------

   procedure Pre_Procedure (Element : in     Asis.Element;
                            Control : in out Asis.Traverse_Control;
                            State   : in out State_Information) is
      use Asis, Asis.Elements, Asis.Expressions;
      use Framework.Reports, Thick_Queries;

      Func_Name : Asis.Element;

      function Formal_Image (Formal : Asis.List_Index) return Wide_String is
         use Asis.Declarations;
         Formal_Elem : constant Asis.Element := Formal_Parameter (State.Assoc (Formal));
      begin
         if Is_Nil (Formal_Elem) then
            -- Positional association
            return Asis.List_Index'Wide_Image (Formal);
         elsif Element_Kind (Formal_Elem) = A_Defining_Name then
            return ' ' & Defining_Name_Image (Formal_Elem);
         else
            return ' ' & Name_Image (Formal_Elem);
         end if;
      end Formal_Image;

      function Func_Image (Func : Asis.Expression) return Wide_String is
         Pfx : Asis.Element;
      begin
         if Expression_Kind (Func) = An_Attribute_Reference then
            Pfx := Prefix (Func);
            if Expression_Kind (Pfx) = A_Selected_Component then
               Pfx := Selector (Pfx);
            end if;
            return Name_Image (Pfx) & ''' & Attribute_Name_Image (Func);
         else
            return To_Title (Name_Image (Func));
         end if;
      end Func_Image;

      procedure Check (Good_Context : Entity_Context) is
      begin
         if Called_By (Good_Context.Rule_Id) = 0 then
            Called_By (Good_Context.Rule_Id)   := State.Param_Pos;
            Called_Func (Good_Context.Rule_Id) := Func_Name;
         else
            Report (Rule_Id,
                    Good_Context,
                    Get_Location (Element),
                    "Call of """
                    & Func_Image (Func_Name)
                    & """ for parameter"
                    & Formal_Image (State.Param_Pos)
                    & " may cause conflict with call of """
                    & Func_Image (Called_Func (Good_Context.Rule_Id))
                    & """ for parameter"
                    & Formal_Image (Called_By (Good_Context.Rule_Id)));
         end if;
      end Check;

   begin
      case Element_Kind (Element) is
         when A_Pragma =>
            -- Do not traverse pragmas
            Control := Abandon_Children;

         when An_Expression =>
            case Expression_Kind (Element) is
               when A_Function_Call =>
                  Func_Name := Prefix (Element);
                  case Expression_Kind (Func_Name) is
                     when A_Selected_Component =>
                        Func_Name := Selector (Func_Name);
                     when An_Explicit_Dereference =>
                        -- Function is called through pointer => not statically determinable
                        Uncheckable (Rule_Id,
                                     False_Negative,
                                     Get_Location (Element),
                                     "Call through access to subprogram");
                        return;
                     when others =>
                        null;
                  end case;

                  if Expression_Type_Kind (Func_Name) = An_Access_Type_Definition then
                     -- Implicit dereference
                     -- Function is called through pointer => not statically determinable
                     Uncheckable (Rule_Id,
                                  False_Negative,
                                  Get_Location (Element),
                                  "Call through access to subprogram");
                     return;
                  end if;

                  declare
                     Context : constant Root_Context'Class
                       := Extended_Matching_Context (Bad_Functions, Ultimate_Name (Func_Name));
                  begin
                     if Context = No_Matching_Context then
                        return;
                     end if;
                     Check (Entity_Context (Context));

                     loop
                        declare
                           Next_Context : constant Root_Context'Class := Next_Matching_Context (Bad_Functions);
                        begin
                           if Next_Context = No_Matching_Context then
                              return;
                           end if;

                           Check (Entity_Context (Next_Context));
                        end;
                     end loop;
                  end;

               when An_Attribute_Reference =>
                  -- Traverse manually the left branch only, in order to avoid processing
                  -- the attribute identifier
                  Traverse (Prefix (Element), Control, State);
                  if Control /= Terminate_Immediately then
                     Control := Abandon_Children;
                  end if;

              when others =>
                  null;
            end case;

         when others =>
            null;
      end case;
   end Pre_Procedure;

   --------------------
   -- Post_Procedure --
   --------------------

   procedure Post_Procedure (Element : in     Asis.Element;
                             Control : in out Asis.Traverse_Control;
                             State   : in out State_Information) is
      pragma Unreferenced (Element, Control, State);
   begin
      null;
   end Post_Procedure;

  -----------------------------------
   -- Process_Call_Or_Instantiation --
   -----------------------------------

   --
   -- GNAT BUG WARNING
   -- Due to an unimplemented feature of ASIS-for-GNAT, we must use Normalized => False
   -- in the following procedure (3 occurrences). The consequence is that we won't detect
   -- defaulted parameters that call a side-effect functions.
   --
   -- You may want to try Normalized => True on your implementation. If it does not make an error
   -- at run-time, you're OK!
   --

   procedure Process_Call_Or_Instantiation (Element : in Asis.Element) is
      use Asis, Asis.Expressions, Thick_Queries;
   begin
      if Rules_Used = 0 then
         return;
      end if;
      Rules_Manager.Enter (Rule_Id);

      Called_By := (others => 0);
      declare
         Associations : aliased constant Asis.Association_List := Actual_Parameters (Element, Normalized => False);
         Control      : Traverse_Control  := Continue;
         State        : State_Information;
      begin
         if Associations'Length < 2 then
            -- no need to check if there is only 1 (or 0!) parameter
            return;
         end if;

         for I in Associations'Range loop
            State := (I, Associations'Unchecked_Access);
            Traverse (Actual_Parameter (Associations (I)), Control, State);
         end loop;
      end;
   end Process_Call_Or_Instantiation;

begin
   Framework.Rules_Manager.Register_Semantic (Rule_Id,
                                              Help    => Help'Access,
                                              Add_Use => Add_Use'Access,
                                              Command => Command'Access,
                                              Prepare => Prepare'Access);
end Rules.Side_Effect_Parameters;
