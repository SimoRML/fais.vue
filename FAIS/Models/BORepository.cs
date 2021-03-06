﻿using System.Collections.Generic;
using System.Linq;

namespace FAIS.Models
{
    public class BORepository
    {
        // private FAISEntities db = new FAISEntities();
        private SGBD s = new SGBD();
        // private BORepositoryGenerator Gen { get; set; }
        public META_BO MetaBO { get; set; }

        public string ExecInsert(string statement, Dictionary<string, object> items)
        {
            return s.Insert(statement, items);

        }

        public string ExecUpdate(string statement, Dictionary<string, object> items)
        {
            return s.Update(statement, items);

        }

        //public BORepository(META_BO metaBO)
        //{
        //    this.MetaBO = metaBO;
        //    Gen = new BORepositoryGenerator(MetaBO);

        //}

        //public object Select()
        //{

        //    var dt = s.Cmd(Gen.GenSelect());
        //    // TODO : SGBD call Cmd
        //    return dt;

        //}

        //public bool Insert(string insetStatements)
        //{
        //    var dt = Gen.GenInsert(insetStatements);
        //    return true;
        //}
    }


    public class BORepositoryGenerator
    {
        private SGBD s = new SGBD();
        private META_BO metaBO;



        public string GenSelect(string Tname)
        {
            // TODO : Filter 
            string select = "";
            //select = "select * from  " + Tname + " ";
            select = @"select c.*, BO.CREATED_BY,BO.CREATED_DATE,BO.UPDATED_BY,BO.UPDATED_DATE,
                        case when convert(varchar,bo.STATUS) = '1'  
                        then 'Nouveau'
                        else bo.STATUS
                        end 'BO_STATUS'
                        from " + Tname + " c " +
                        "inner join BO on BO.BO_ID = c.BO_ID AND BO.STATUS != 'deleted'";
            return select;
        }
        public string GenSelectFields(string Tname, List<string> fields, string where="")
        {
            string fieldString = "c." + fields.Aggregate((a, b) => a + ", c." + b);
            // TODO : Filter 
            string select = "";
            //select = "select * from  " + Tname + " ";
            select = "select "+ fieldString + @", BO.CREATED_BY,BO.CREATED_DATE,BO.UPDATED_BY,BO.UPDATED_DATE,
                        case when convert(varchar,bo.STATUS) = '1'  
                        then 'Nouveau'
                        else bo.STATUS
                        end 'BO_STATUS'
                        from " + Tname + @" c " +
                        " inner join BO on BO.BO_ID = c.BO_ID AND BO.STATUS != 'deleted' " + where ;
            return select;
        }

        public string GenSelectIncludeSubForm(META_BO meta, string subform)
        {
            // TODO : Filter 
            string select = "";
            //select = "select * from  " + Tname + " ";
            select = @"select c.*, BO.CREATED_BY,BO.CREATED_DATE,BO.UPDATED_BY,BO.UPDATED_DATE,
                        case when convert(varchar,bo.STATUS) = '1'  
                        then 'Nouveau'
                        else bo.STATUS
                        end 'BO_STATUS' " +
                        (subform == null ? "" : ", (SELECT * FROM " + subform + @"  where BO_ID in (select BO_CHILD_ID from BO_CHILDS where BO_PARENT_ID = c.BO_ID) FOR JSON PATH) as sub")
                         + " from " + meta.BO_DB_NAME + @" c 
                         inner join BO on BO.BO_ID = c.BO_ID AND BO.STATUS != 'deleted'";
            return select;
        }

        public string GenSelectChilds(string Tname, long parentId)
        {
            // TODO : Filter 
            string select = "";
            select = "select c.* from  " + Tname + " c inner join BO on BO.BO_ID = c.BO_ID AND BO.STATUS != 'deleted' where c.BO_ID in (select BO_CHILD_ID from BO_CHILDS where BO_PARENT_ID = " + parentId + ")";

            return select;
        }
        // TODO GenSelectOne (Switch to filter Model)

        public string GenSelectOne(string Tname)
        {
            // TODO : Filter 
            string select = "";
            select = "select * from  " + Tname + " where BO_ID=@BO_ID";

            return select;
        }

        // TODO : GenUpdate
        // TODO : GenDelete


    }
}
