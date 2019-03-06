﻿//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated from a template.
//
//     Manual changes to this file may cause unexpected behavior in your application.
//     Manual changes to this file will be overwritten if the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

namespace FAIS.Models
{
    using System;
    using System.Data.Entity;
    using System.Data.Entity.Infrastructure;
    using System.Data.Entity.Core.Objects;
    using System.Linq;
    
    public partial class FAISEntities : DbContext
    {
        public FAISEntities()
            : base("name=FAISEntities")
        {
        }
    
        protected override void OnModelCreating(DbModelBuilder modelBuilder)
        {
            throw new UnintentionalCodeFirstException();
        }
    
        public virtual DbSet<BO> BO { get; set; }
        public virtual DbSet<BO_CHILDS> BO_CHILDS { get; set; }
        public virtual DbSet<META_BO> META_BO { get; set; }
        public virtual DbSet<META_FIELD> META_FIELD { get; set; }
        public virtual DbSet<VERSIONS> VERSIONS { get; set; }
        public virtual DbSet<PAGE> PAGE { get; set; }
        public virtual DbSet<PlusSequence> PlusSequence { get; set; }
    
        public virtual int MoveBoToCurrentVersion(Nullable<long> bO_ID)
        {
            var bO_IDParameter = bO_ID.HasValue ?
                new ObjectParameter("BO_ID", bO_ID) :
                new ObjectParameter("BO_ID", typeof(long));
    
            return ((IObjectContextAdapter)this).ObjectContext.ExecuteFunction("MoveBoToCurrentVersion", bO_IDParameter);
        }
    
        public virtual ObjectResult<string> PlusSequenceNextID(string cle, string tableName, Nullable<int> stepBy)
        {
            var cleParameter = cle != null ?
                new ObjectParameter("cle", cle) :
                new ObjectParameter("cle", typeof(string));
    
            var tableNameParameter = tableName != null ?
                new ObjectParameter("TableName", tableName) :
                new ObjectParameter("TableName", typeof(string));
    
            var stepByParameter = stepBy.HasValue ?
                new ObjectParameter("stepBy", stepBy) :
                new ObjectParameter("stepBy", typeof(int));
    
            return ((IObjectContextAdapter)this).ObjectContext.ExecuteFunction<string>("PlusSequenceNextID", cleParameter, tableNameParameter, stepByParameter);
        }
    }
}
